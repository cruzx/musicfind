import Foundation
import Combine
import SpotifyiOS

enum SpotifyAppRemoteError: LocalizedError {
    case notAuthorized
    case notConnected
    case unavailable
    case spotifyNotInstalled

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Spotify 播放控制尚未授权。"
        case .notConnected:
            return "Spotify 播放控制尚未连接。"
        case .unavailable:
            return "Spotify 播放控制暂时不可用。"
        case .spotifyNotInstalled:
            return "未检测到 Spotify App。"
        }
    }
}

@MainActor
final class SpotifyAppRemoteController: NSObject, ObservableObject {
    static let shared = SpotifyAppRemoteController()

    @Published private(set) var isConnected = false
    @Published private(set) var isAuthorized = false
    var errorHandler: ((String) -> Void)?
    var playbackStateHandler: ((String, Bool) -> Void)?

    private let accessTokenKey = "spotifyAppRemoteAccessToken"
    private var pendingConnectionContinuations: [CheckedContinuation<Bool, Never>] = []
    private var pendingPlayURI: String?

    private lazy var configuration: SPTConfiguration = {
        SPTConfiguration(
            clientID: SpotifyAuthConfig.clientID,
            redirectURL: URL(string: SpotifyAuthConfig.appRemoteRedirectURI)!
        )
    }()

    private lazy var appRemote: SPTAppRemote = {
        let remote = SPTAppRemote(configuration: configuration, logLevel: .error)
        remote.delegate = self
        if let token = UserDefaults.standard.string(forKey: accessTokenKey), token.isEmpty == false {
            remote.connectionParameters.accessToken = token
            isAuthorized = true
        }
        return remote
    }()

    private override init() {
        super.init()
    }

    func authorizePlaybackControl() {
        appRemote.authorizeAndPlayURI("") { _ in }
    }

    func playIfConnected(uri: String) async throws {
        guard appRemote.isConnected else { throw SpotifyAppRemoteError.notConnected }
        try await playOnConnectedRemote(uri: uri)
    }

    @discardableResult
    func handleCallbackURL(_ url: URL) -> Bool {
        guard url.scheme?.caseInsensitiveCompare(configuration.redirectURL.scheme ?? "") == .orderedSame else {
            return false
        }
        let callbackItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        print("[SPOTIFY_REMOTE] callback fields: \(callbackItems.map(\.name).joined(separator: ", "))")
        let parameters = appRemote.authorizationParameters(from: url)
        if let token = parameters?[SPTAppRemoteAccessTokenKey] as? String, token.isEmpty == false {
            UserDefaults.standard.set(token, forKey: accessTokenKey)
            UserDefaults.standard.synchronize()
            appRemote.connectionParameters.accessToken = token
            isAuthorized = true
            print("[SPOTIFY_REMOTE] authorization callback accepted")
            appRemote.connect()
            return true
        }
        let callbackErrorDescription = callbackItems
            .first { $0.name == "error_description" }?
            .value ?? ""
        if callbackErrorDescription.localizedCaseInsensitiveContains("timed out") {
            reportError("Spotify 授权请求超时，请检查手机网络或 VPN 是否能访问 accounts.spotify.com。")
        } else if let errorDescription = parameters?[SPTAppRemoteErrorDescriptionKey] as? String {
            reportError("播放控制授权失败：\(errorDescription)")
        } else {
            reportError("没有收到 Spotify 播放控制令牌，请检查 Redirect URI 配置。")
        }
        return false
    }

    func reconnectIfAuthorized() {
        guard isAuthorized, appRemote.isConnected == false else { return }
        appRemote.connect()
    }

    func disconnect() {
        guard appRemote.isConnected else { return }
        appRemote.disconnect()
    }

    func clearAuthorization() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: accessTokenKey)
        appRemote.connectionParameters.accessToken = nil
        isAuthorized = false
        isConnected = false
        pendingPlayURI = nil
        resumeConnectionWaiters(false)
    }

    func play(uri: String) async throws {
        guard isAuthorized else { throw SpotifyAppRemoteError.notAuthorized }
        guard await ensureConnected() else { throw SpotifyAppRemoteError.notConnected }
        try await playOnConnectedRemote(uri: uri)
    }

    private func playOnConnectedRemote(uri: String) async throws {
        guard let playerAPI = appRemote.playerAPI else { throw SpotifyAppRemoteError.unavailable }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            playerAPI.play(uri) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func pause() async throws {
        guard isAuthorized else { throw SpotifyAppRemoteError.notAuthorized }
        guard await ensureConnected() else { throw SpotifyAppRemoteError.notConnected }
        guard let playerAPI = appRemote.playerAPI else { throw SpotifyAppRemoteError.unavailable }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            playerAPI.pause { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func ensureConnected() async -> Bool {
        if appRemote.isConnected { return true }
        guard isAuthorized else { return false }
        appRemote.connect()

        return await withCheckedContinuation { continuation in
            pendingConnectionContinuations.append(continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.resumeConnectionWaiters(self.appRemote.isConnected)
            }
        }
    }

    private func resumeConnectionWaiters(_ connected: Bool) {
        let waiters = pendingConnectionContinuations
        pendingConnectionContinuations.removeAll()
        waiters.forEach { $0.resume(returning: connected) }
    }

    private func reportError(_ message: String) {
        print("[SPOTIFY_REMOTE] \(message)")
        errorHandler?(message)
    }
}

extension SpotifyAppRemoteController: SPTAppRemoteDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        print("[SPOTIFY_REMOTE] connected")
        isConnected = true
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { _, _ in })
        resumeConnectionWaiters(true)
        if let pendingPlayURI {
            appRemote.playerAPI?.play(pendingPlayURI) { [weak self] _, error in
                if let error {
                    self?.reportError("播放失败：\(error.localizedDescription)")
                } else {
                    self?.pendingPlayURI = nil
                }
            }
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        isConnected = false
        resumeConnectionWaiters(false)
        if let error {
            reportError("Spotify 播放连接已断开：\(error.localizedDescription)")
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        isConnected = false
        resumeConnectionWaiters(false)
        reportError("Spotify 播放连接失败：\(error?.localizedDescription ?? "未知错误")")
    }
}

extension SpotifyAppRemoteController: SPTAppRemotePlayerStateDelegate {
    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        playbackStateHandler?(playerState.track.uri, playerState.isPaused == false)
    }
}
