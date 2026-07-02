//
//  ContentView.swift
//  musicfind
//
//  Created by 项程锦 on 2026/6/30.
//

import SwiftUI
import UIKit
import CoreMotion
import Combine
import MediaPlayer
import AuthenticationServices
import CryptoKit

struct ContentView: View {
    @State private var activeTab: AppTab = .home
    @State private var nowPlaying = DemoSong.library[0]
    @StateObject private var musicConnector = MusicConnectionManager()
    @State private var isPlayerCardVisible = false
    @State private var isPlayerCardExpanded = false
    @State private var isPlayerCardContentVisible = false
    @State private var isPlayerPillHiddenForExpansion = false
    @State private var playerMorphProgress: CGFloat = 0
    @State private var playerPillFrame: CGRect = .zero
    @State private var homeDriftAmount: CGFloat = 0
    @State private var homeSongs: [DemoSong] = []
    @State private var homePendingSongs: [DemoSong] = []
    @State private var homeFlipProgressByID: [Int: CGFloat] = [:]
    @State private var homeFlipVariations: [Int: HomeFlipVariation] = [:]
    @State private var isHomeFlipping = false
    @State private var homeFlipGeneration = UUID()
    @StateObject private var shakeObserver = ShakeMotionObserver()
    @State private var homeIdleTask: Task<Void, Never>?
    @State private var homeFlipTask: Task<Void, Never>?
    @Namespace private var playerExpansionNamespace

    private let spacing: CGFloat = 8
    private let columns = 0..<4
    private var songs: [DemoSong] {
        musicConnector.librarySongs.isEmpty ? DemoSong.library : musicConnector.librarySongs
    }
    private var visibleHomeSongs: [DemoSong] {
        homeSongs.isEmpty ? songs : homeSongs
    }

    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.027, blue: 0.098)
                .ignoresSafeArea()

            if activeTab == .settings {
                ProfilePage(connector: musicConnector, activeTab: $activeTab)
                    .transition(.opacity)
            } else if isPlayerCardVisible == false {
                ScrollView(showsIndicators: false) {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(columns), id: \.self) { column in
                            LazyVStack(spacing: spacing) {
                                ForEach(songSlotsForColumn(column)) { slot in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        registerHomeInteraction()
                                        nowPlaying = slot.song
                                        Task { await musicConnector.play(slot.song) }
                                    } label: {
                                        HomeFlipSongSquare(
                                            frontSong: visibleHomeSongs[slot.id],
                                            backSong: homePendingSongs.indices.contains(slot.id) ? homePendingSongs[slot.id] : visibleHomeSongs[slot.id],
                                            isPlaying: slot.song.id == nowPlaying.id,
                                            progress: homeFlipLocalProgress(for: slot),
                                            variation: homeFlipVariations[slot.id] ?? .zero
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, topOffset(for: column))
                            .offset(y: homeDriftOffset(for: column))
                        }
                    }
                    .padding(.horizontal, spacing)
                    .padding(.top, spacing)
                    .padding(.bottom, 92)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            registerHomeInteraction()
                        }
                )
            }

            TopGlassFade()
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

            BottomGlassFade()
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)

            if activeTab != .settings {
                VStack {
                    HStack {
                        DateBadge()
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .offset(x: 20, y: 40)

                    Spacer()
                }
                .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                BottomNavigationBar(
                    activeTab: $activeTab,
                    nowPlaying: nowPlaying,
                    isPlaying: musicConnector.isPlaying,
                    namespace: playerExpansionNamespace,
                    isPlayerCardVisible: isPlayerPillHiddenForExpansion,
                    playerPillFrame: $playerPillFrame,
                    onPlayerTap: showPlayerCard,
                    onTogglePlayback: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await musicConnector.togglePlayback(for: nowPlaying) }
                    }
                )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
            }

            if isPlayerCardVisible {
                Color.black.opacity(isPlayerCardContentVisible ? 0.34 : 0.0)
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.18), value: isPlayerCardContentVisible)
                    .onTapGesture(perform: hidePlayerCard)

                GeometryReader { proxy in
                    let expandedWidth = proxy.size.width - 12
                    let expandedHeight = proxy.size.height - 66
                    let collapsedFrame = playerPillFrame == .zero
                        ? CGRect(x: (proxy.size.width - 226) / 2, y: proxy.size.height - 65, width: 226, height: 53)
                        : playerPillFrame
                    let targetFrame = CGRect(
                        x: (proxy.size.width - expandedWidth) / 2,
                        y: 48,
                        width: expandedWidth,
                        height: expandedHeight
                    )
                    let widthProgress = 1 - pow(1 - playerMorphProgress, 2.2)
                    let topProgress = min(1, playerMorphProgress * 1.18)
                    let bottomProgress = pow(playerMorphProgress, 1.85)
                    let currentLeft = collapsedFrame.minX + (targetFrame.minX - collapsedFrame.minX) * widthProgress
                    let currentRight = collapsedFrame.maxX + (targetFrame.maxX - collapsedFrame.maxX) * widthProgress
                    let currentTop = collapsedFrame.minY + (targetFrame.minY - collapsedFrame.minY) * topProgress
                    let currentBottom = collapsedFrame.maxY + (targetFrame.maxY - collapsedFrame.maxY) * bottomProgress
                    let currentWidth = currentRight - currentLeft
                    let currentHeight = currentBottom - currentTop
                    let currentCornerRadius = collapsedFrame.height / 2 + (34 - collapsedFrame.height / 2) * playerMorphProgress
                    let currentSurfaceOpacity = 0.74 + (1.0 - 0.74) * playerMorphProgress
                    let currentCenterX = currentLeft + currentWidth / 2
                    let currentCenterY = currentTop + currentHeight / 2

                    ExpandedPlayerCard(
                        songs: songs,
                        nowPlaying: $nowPlaying,
                        namespace: playerExpansionNamespace,
                        cornerRadius: currentCornerRadius,
                        surfaceOpacity: currentSurfaceOpacity,
                        isContentVisible: isPlayerCardContentVisible,
                        isPlaybackActive: { song in
                            musicConnector.isPlaying && musicConnector.playingSongID == song.id
                        },
                        onClose: hidePlayerCard,
                        onSongChange: { song in
                            Task { await musicConnector.togglePlayback(for: song) }
                        }
                    )
                    .frame(
                        width: currentWidth,
                        height: currentHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
                    .position(x: currentCenterX, y: currentCenterY)
                    .animation(.smooth(duration: 0.28, extraBounce: 0.0), value: playerMorphProgress)
                }
                .ignoresSafeArea()
                .transition(.identity)
            }
        }
        .task {
            await musicConnector.refreshAppleMusicLibraryIfPossible()
        }
        .onAppear {
            syncHomeSongsIfNeeded()
            shakeObserver.start()
            scheduleHomeIdleDrift()
        }
        .onDisappear {
            homeFlipTask?.cancel()
            shakeObserver.stop()
        }
        .onChange(of: activeTab) { _, newValue in
            if newValue == .home {
                scheduleHomeIdleDrift()
            } else {
                stopHomeDrift()
            }
        }
        .onChange(of: isPlayerCardVisible) { _, isVisible in
            if isVisible {
                stopHomeDrift()
            } else if activeTab == .home {
                scheduleHomeIdleDrift()
            }
        }
        .onChange(of: songs.map(\.id)) { _, _ in
            syncHomeSongsIfNeeded(force: true)
        }
        .onChange(of: shakeObserver.shakeCount) { _, _ in
            reshuffleHomeSongsWithFlip()
        }
    }

    private func showPlayerCard() {
        guard !isPlayerCardVisible else { return }
        stopHomeDrift()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        activeTab = .player
        isPlayerCardExpanded = false
        isPlayerCardContentVisible = false
        isPlayerPillHiddenForExpansion = false
        playerMorphProgress = 0

        isPlayerCardVisible = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard isPlayerCardVisible else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                isPlayerPillHiddenForExpansion = true
            }
            withAnimation(.smooth(duration: 0.30, extraBounce: 0.02)) {
                playerMorphProgress = 1
                isPlayerCardExpanded = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
            guard isPlayerCardVisible else { return }
            withAnimation(.easeOut(duration: 0.1)) {
                isPlayerCardContentVisible = true
            }
        }
    }

    private func hidePlayerCard() {
        guard isPlayerCardVisible else { return }

        withAnimation(.easeIn(duration: 0.12)) {
            isPlayerCardContentVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.smooth(duration: 0.26, extraBounce: 0.0)) {
                playerMorphProgress = 0
                isPlayerCardExpanded = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) {
            isPlayerCardVisible = false
            isPlayerCardContentVisible = false
            isPlayerCardExpanded = false
            playerMorphProgress = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) {
            withAnimation(.easeOut(duration: 0.08)) {
                isPlayerPillHiddenForExpansion = false
            }
        }
    }

    private func songsForColumn(_ column: Int) -> [DemoSong] {
        visibleHomeSongs.enumerated().compactMap { index, song in
            index % 4 == column ? song : nil
        }
    }

    private func songSlotsForColumn(_ column: Int) -> [HomeSongSlot] {
        visibleHomeSongs.indices.compactMap { index in
            guard index % 4 == column else { return nil }
            return HomeSongSlot(
                id: index,
                row: index / 4,
                column: column,
                song: displayedHomeSong(at: index)
            )
        }
    }

    private func displayedHomeSong(at index: Int) -> DemoSong {
        let slot = HomeSongSlot(id: index, row: index / 4, column: index % 4, song: visibleHomeSongs[index])
        let localProgress = homeFlipLocalProgress(for: slot)
        if isHomeFlipping, localProgress >= 0.5, homePendingSongs.indices.contains(index) {
            return homePendingSongs[index]
        }
        return visibleHomeSongs[index]
    }

    private func homeFlipLocalProgress(for slot: HomeSongSlot) -> CGFloat {
        guard isHomeFlipping else { return 1 }
        return min(max(homeFlipProgressByID[slot.id] ?? 0, 0), 1)
    }

    private func syncHomeSongsIfNeeded(force: Bool = false) {
        let currentIDs = homeSongs.map(\.id)
        let sourceIDs = songs.map(\.id)
        if force || currentIDs.sorted() != sourceIDs.sorted() {
            homeSongs = songs
            homePendingSongs = []
            homeFlipProgressByID = [:]
            isHomeFlipping = false
        }
    }

    private func reshuffleHomeSongsWithFlip() {
        guard activeTab == .home, isPlayerCardVisible == false, songs.count > 1, !isHomeFlipping else { return }
        registerHomeInteraction()
        homeFlipTask?.cancel()

        let nextSongs = shuffledHomeSongs()
        homePendingSongs = nextSongs
        homeFlipVariations = makeHomeFlipVariations(count: nextSongs.count)
        homeFlipProgressByID = Dictionary(uniqueKeysWithValues: nextSongs.indices.map { ($0, CGFloat(0)) })
        let generation = UUID()
        homeFlipGeneration = generation
        isHomeFlipping = true

        homeFlipTask = Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()

            let timeline = nextSongs.indices.map { index -> (index: Int, startMs: Int, duration: Double) in
                let row = index / 4
                let column = index % 4
                let variation = homeFlipVariations[index] ?? .zero
                let rowBase = row * 92
                let columnScatter = [52, 7, 86, 25][column]
                let randomScatter = Int((variation.delay * 1000).rounded())
                let startMs = max(0, rowBase + columnScatter + randomScatter)
                let duration = Double(variation.durationScale) * 0.48
                return (index, startMs, duration)
            }

            for item in timeline {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(item.startMs))
                    guard !Task.isCancelled, isHomeFlipping, homeFlipGeneration == generation else { return }
                    generator.impactOccurred(intensity: 0.52)
                    withAnimation(.interactiveSpring(response: item.duration, dampingFraction: 0.78, blendDuration: 0.02)) {
                        homeFlipProgressByID[item.index] = 1
                    }
                }
            }

            let finalDelay = (timeline.map { $0.startMs }.max() ?? 0) + 760
            try? await Task.sleep(for: .milliseconds(finalDelay))
            guard !Task.isCancelled else { return }
            homeSongs = nextSongs
            homePendingSongs = []
            homeFlipVariations = [:]
            homeFlipProgressByID = [:]
            isHomeFlipping = false
        }
    }

    private func makeHomeFlipVariations(count: Int) -> [Int: HomeFlipVariation] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { index in
            (
                index,
                HomeFlipVariation(
                    delay: CGFloat.random(in: -0.020...0.170),
                    durationScale: CGFloat.random(in: 0.72...1.48),
                    tilt: Double.random(in: -7...7),
                    lift: CGFloat.random(in: -5...6)
                )
            )
        })
    }

    private func shuffledHomeSongs() -> [DemoSong] {
        let shuffled = songs.shuffled()
        guard let first = shuffled.first, first.id == visibleHomeSongs.first?.id, shuffled.count > 1 else {
            return shuffled
        }
        return Array(shuffled.dropFirst()) + [first]
    }

    private func registerHomeInteraction() {
        guard activeTab == .home else { return }
        scheduleHomeIdleDrift()
    }

    private func scheduleHomeIdleDrift() {
        homeIdleTask?.cancel()
        if homeDriftAmount != 0 {
            withAnimation(.smooth(duration: 0.32, extraBounce: 0.0)) {
                homeDriftAmount = 0
            }
        }
        homeIdleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            guard activeTab == .home, isPlayerCardVisible == false else { return }
            var target: CGFloat = 1
            while !Task.isCancelled, activeTab == .home, isPlayerCardVisible == false {
                withAnimation(.easeInOut(duration: 9)) {
                    homeDriftAmount = target
                }
                target *= -1
                try? await Task.sleep(for: .seconds(9))
            }
        }
    }

    private func stopHomeDrift() {
        homeIdleTask?.cancel()
        homeIdleTask = nil
        withAnimation(.smooth(duration: 0.32, extraBounce: 0.0)) {
            homeDriftAmount = 0
        }
    }

    private func homeDriftOffset(for column: Int) -> CGFloat {
        let distance: CGFloat = 32 * homeDriftAmount
        return (column == 0 || column == 2) ? -distance : distance
    }

    private func topOffset(for column: Int) -> CGFloat {
        switch column {
        case 0: 18
        case 2: 28
        default: 0
        }
    }

}

private enum AppTab {
    case home
    case player
    case settings
}

private struct HomeSongSlot: Identifiable {
    let id: Int
    let row: Int
    let column: Int
    let song: DemoSong
}

private struct HomeFlipVariation {
    let delay: CGFloat
    let durationScale: CGFloat
    let tilt: Double
    let lift: CGFloat

    static let zero = HomeFlipVariation(delay: 0, durationScale: 1, tilt: 0, lift: 0)
}

private struct DateBadge: View {
    private let dateText = Date.now.formatted(
        .dateTime
            .day()
            .month(.wide)
            .locale(Locale(identifier: "en_US_POSIX"))
    )
        .lowercased()

    var body: some View {
        Text(dateText)
            .font(.system(size: 50, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct ProfilePage: View {
    @ObservedObject var connector: MusicConnectionManager
    @Binding var activeTab: AppTab

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                BadgePhysicsPanel()
                    .frame(height: proxy.size.height * 0.34)
                    .padding(.top, proxy.safeAreaInsets.top + 18)

                VStack(spacing: 14) {
                    MusicConnectButton(
                        title: "连接 Spotify",
                        subtitle: connector.spotifyStatusText,
                        systemName: "music.note",
                        tint: Color(red: 0.1, green: 0.84, blue: 0.36),
                        isLoading: connector.isConnectingSpotify
                    ) {
                        Task { await connector.connectSpotify() }
                    }

                    MusicConnectButton(
                        title: "连接 Apple Music",
                        subtitle: connector.appleMusicStatusText,
                        systemName: "music.note.list",
                        tint: Color(red: 1.0, green: 0.18, blue: 0.35),
                        isLoading: connector.isConnectingAppleMusic
                    ) {
                        Task {
                            await connector.connectAppleMusic()
                            if connector.isAppleMusicReady {
                                withAnimation(.smooth(duration: 0.22, extraBounce: 0.0)) {
                                    activeTab = .home
                                }
                            }
                        }
                    }

                    if let message = connector.message {
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 28)

                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MusicConnectButton: View {
    let title: String
    let subtitle: String
    let systemName: String
    let tint: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(.white.opacity(0.72))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(.black.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .liquidGlassSurface(cornerRadius: 24, isInteractive: true)
    }
}

@MainActor
private final class MusicConnectionManager: ObservableObject {
    @Published var isConnectingAppleMusic = false
    @Published var isConnectingSpotify = false
    @Published var librarySongs: [DemoSong] = []
    @Published var message: String?
    @Published var playingSongID: Int?
    @Published var isPlaying = false

    @AppStorage("appleMusicConnected") private var appleMusicConnected = false
    @AppStorage("spotifyAccessToken") private var spotifyAccessToken = ""
    @AppStorage("spotifyRefreshToken") private var spotifyRefreshToken = ""
    @AppStorage("spotifyTokenExpiresAt") private var spotifyTokenExpiresAt = 0.0

    private let spotifyAuthenticator = SpotifyPKCEAuthenticator()

    var appleMusicStatusText: String {
        appleMusicConnected ? "已连接" : "请求系统授权"
    }

    var isAppleMusicReady: Bool {
        appleMusicConnected && MPMediaLibrary.authorizationStatus() == .authorized
    }

    var spotifyStatusText: String {
        spotifyAccessToken.isEmpty ? "通过 Spotify 登录授权" : "已连接"
    }

    func connectAppleMusic() async {
        guard !isConnectingAppleMusic else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isConnectingAppleMusic = true
        defer { isConnectingAppleMusic = false }

        let status = await requestMediaLibraryAuthorization()
        switch status {
        case .authorized:
            appleMusicConnected = true
            loadAppleMusicLibrary()
        case .denied:
            appleMusicConnected = false
            message = "Apple Music / 媒体资料库授权被拒绝，可以在系统设置里重新开启。"
        case .restricted:
            appleMusicConnected = false
            message = "当前设备限制了媒体资料库授权。"
        case .notDetermined:
            appleMusicConnected = false
            message = "媒体资料库尚未完成授权。"
        @unknown default:
            appleMusicConnected = false
            message = "媒体资料库授权状态未知。"
        }
    }

    func refreshAppleMusicLibraryIfPossible() async {
        guard appleMusicConnected || MPMediaLibrary.authorizationStatus() == .authorized else { return }
        appleMusicConnected = true
        loadAppleMusicLibrary()
    }

    private func requestMediaLibraryAuthorization() async -> MPMediaLibraryAuthorizationStatus {
        await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func loadAppleMusicLibrary() {
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()

        let items = mediaItemsFromLibrary()
        let palettes = DemoSong.library.map(\.colors)
        librarySongs = items.prefix(120).enumerated().map { index, item in
            let artworkImage = item.artwork?.image(at: CGSize(width: 360, height: 360))
            let magicColor = artworkImage?.magicAverageColor ?? UIColor(songPalette: palettes[index % palettes.count])
            return DemoSong(
                id: 10_000 + index,
                title: item.title ?? "Untitled",
                artist: item.artist ?? "Unknown Artist",
                colors: palettes[index % palettes.count],
                mediaItem: item,
                artworkImage: artworkImage,
                backdropImage: artworkImage?.playerBackdropImage,
                magicColor: Color(uiColor: magicColor)
            )
        }
        message = librarySongs.isEmpty
            ? "Apple Music 已授权，但没有读到已加入资料库的歌曲。请先在 Apple Music 里把歌曲添加到资料库，并确认系统设置里允许访问媒体与 Apple Music。"
            : "已读取 \(librarySongs.count) 首歌曲"
    }

    private func mediaItemsFromLibrary() -> [MPMediaItem] {
        let queryItems = [
            MPMediaQuery.songs().items ?? [],
            MPMediaQuery.albums().items ?? [],
            MPMediaQuery.artists().items ?? [],
            MPMediaQuery.playlists().collections?.flatMap(\.items) ?? []
        ].flatMap { $0 }

        var seenIDs = Set<MPMediaEntityPersistentID>()
        var seenSongs = Set<String>()
        return queryItems.compactMap { item in
            guard item.mediaType.contains(.music) else { return nil }
            guard let title = item.title, title.isEmpty == false else { return nil }
            guard seenIDs.insert(item.persistentID).inserted else { return nil }
            let artist = item.artist ?? ""
            let songKey = normalizedSongKey(title: title, artist: artist)
            guard seenSongs.insert(songKey).inserted else { return nil }
            return item
        }
    }

    private func normalizedSongKey(title: String, artist: String) -> String {
        "\(title)|\(artist)"
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func play(_ song: DemoSong) async {
        guard let mediaItem = song.mediaItem else { return }
        let player = MPMusicPlayerController.applicationMusicPlayer
        player.setQueue(with: MPMediaItemCollection(items: [mediaItem]))
        player.play()
        playingSongID = song.id
        isPlaying = true
        message = "正在播放：\(song.title)"
    }

    func togglePlayback(for song: DemoSong) async {
        guard let mediaItem = song.mediaItem else { return }
        let player = MPMusicPlayerController.applicationMusicPlayer
        if player.playbackState == .playing, player.nowPlayingItem?.persistentID == mediaItem.persistentID {
            player.pause()
            playingSongID = song.id
            isPlaying = false
            message = "已暂停：\(song.title)"
        } else {
            player.setQueue(with: MPMediaItemCollection(items: [mediaItem]))
            player.play()
            playingSongID = song.id
            isPlaying = true
            message = "正在播放：\(song.title)"
        }
    }

    func connectSpotify() async {
        guard !isConnectingSpotify else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isConnectingSpotify = true
        defer { isConnectingSpotify = false }

        do {
            let token = try await spotifyAuthenticator.authorize()
            spotifyAccessToken = token.accessToken
            spotifyRefreshToken = token.refreshToken ?? spotifyRefreshToken
            spotifyTokenExpiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn)).timeIntervalSince1970
            message = "Spotify 已连接"
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: Int
    let refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private enum SpotifyAuthError: LocalizedError {
    case missingClientID
    case invalidAuthorizeURL
    case missingCallbackCode
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Spotify 还缺少 Client ID。请在 Spotify Developer 后台创建 App，并把 Client ID 填到 SpotifyAuthConfig.clientID。"
        case .invalidAuthorizeURL:
            return "Spotify 授权链接生成失败。"
        case .missingCallbackCode:
            return "Spotify 没有返回授权码。"
        case .invalidTokenResponse:
            return "Spotify token 返回内容无法解析。"
        }
    }
}

private enum SpotifyAuthConfig {
    static let clientID = ""
    static let redirectURI = "musicfind://spotify-auth"
    static let callbackScheme = "musicfind"
    static let scopes = [
        "user-read-email",
        "user-read-private",
        "user-library-read",
        "playlist-read-private"
    ]
}

@MainActor
private final class SpotifyPKCEAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize() async throws -> SpotifyTokenResponse {
        guard SpotifyAuthConfig.clientID.isEmpty == false else {
            throw SpotifyAuthError.missingClientID
        }

        let verifier = Self.randomCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: SpotifyAuthConfig.clientID),
            URLQueryItem(name: "scope", value: SpotifyAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: SpotifyAuthConfig.redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]

        guard let authURL = components?.url else {
            throw SpotifyAuthError.invalidAuthorizeURL
        }

        let callbackURL = try await authenticate(with: authURL)
        guard
            let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value == state,
            let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw SpotifyAuthError.missingCallbackCode
        }

        return try await exchangeToken(code: code, verifier: verifier)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func authenticate(with url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: SpotifyAuthConfig.callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: SpotifyAuthError.missingCallbackCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    private func exchangeToken(code: String, verifier: String) async throws -> SpotifyTokenResponse {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
            throw SpotifyAuthError.invalidTokenResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyAuthConfig.clientID),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: SpotifyAuthConfig.redirectURI),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw SpotifyAuthError.invalidTokenResponse
        }

        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }

    private static func randomCodeVerifier() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<96).map { _ in characters.randomElement(using: &generator)! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct BadgePhysicsPanel: View {
    @StateObject private var motion = MotionGravityObserver()
    @State private var badges: [PhysicsBadge] = PhysicsBadge.samples
    @State private var lastSize: CGSize = .zero

    private let frameRate = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(badges) { badge in
                    BadgeCircle(badge: badge)
                        .position(badge.position)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear {
                motion.start()
                resetBadges(in: proxy.size)
            }
            .onDisappear {
                motion.stop()
            }
            .onChange(of: proxy.size) { newSize in
                resetBadges(in: newSize)
            }
            .onReceive(frameRate) { _ in
                stepBadges(in: proxy.size)
            }
        }
    }

    private func resetBadges(in size: CGSize) {
        guard size.width > 10, size.height > 10, size != lastSize else { return }
        lastSize = size
        let columns: [CGFloat] = [0.20, 0.40, 0.60, 0.80]
        badges = badges.enumerated().map { index, badge in
            var next = badge
            let column = columns[index % columns.count]
            let row = CGFloat(index / columns.count)
            next.position = CGPoint(x: size.width * column, y: 54 + row * 54)
            next.velocity = CGPoint(x: CGFloat(index % 2 == 0 ? 22 : -18), y: CGFloat(index % 3 == 0 ? 10 : -12))
            return next
        }
    }

    private func stepBadges(in size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }

        var next = badges
        let gravity = motion.gravity
        let acceleration = CGPoint(x: CGFloat(gravity.x) * 760, y: CGFloat(-gravity.y) * 760)
        let dt: CGFloat = 1.0 / 60.0
        let damping: CGFloat = 0.986

        for index in next.indices {
            next[index].velocity.x = (next[index].velocity.x + acceleration.x * dt) * damping
            next[index].velocity.y = (next[index].velocity.y + acceleration.y * dt) * damping
            next[index].position.x += next[index].velocity.x * dt
            next[index].position.y += next[index].velocity.y * dt

            let radius = next[index].radius
            if next[index].position.x < radius {
                next[index].position.x = radius
                next[index].velocity.x = abs(next[index].velocity.x) * 0.72
            } else if next[index].position.x > size.width - radius {
                next[index].position.x = size.width - radius
                next[index].velocity.x = -abs(next[index].velocity.x) * 0.72
            }

            if next[index].position.y < radius {
                next[index].position.y = radius
                next[index].velocity.y = abs(next[index].velocity.y) * 0.72
            } else if next[index].position.y > size.height - radius {
                next[index].position.y = size.height - radius
                next[index].velocity.y = -abs(next[index].velocity.y) * 0.72
            }
        }

        for left in next.indices {
            for right in next.indices where right > left {
                resolveCollision(left, right, badges: &next)
            }
        }

        badges = next
    }

    private func resolveCollision(_ left: Int, _ right: Int, badges: inout [PhysicsBadge]) {
        let delta = CGPoint(
            x: badges[right].position.x - badges[left].position.x,
            y: badges[right].position.y - badges[left].position.y
        )
        let distance = max(0.001, sqrt(delta.x * delta.x + delta.y * delta.y))
        let minimumDistance = badges[left].radius + badges[right].radius
        guard distance < minimumDistance else { return }

        let normal = CGPoint(x: delta.x / distance, y: delta.y / distance)
        let overlap = (minimumDistance - distance) * 0.5
        badges[left].position.x -= normal.x * overlap
        badges[left].position.y -= normal.y * overlap
        badges[right].position.x += normal.x * overlap
        badges[right].position.y += normal.y * overlap

        let relativeVelocity = CGPoint(
            x: badges[right].velocity.x - badges[left].velocity.x,
            y: badges[right].velocity.y - badges[left].velocity.y
        )
        let speed = relativeVelocity.x * normal.x + relativeVelocity.y * normal.y
        guard speed < 0 else { return }

        let impulse = -speed * 0.82
        badges[left].velocity.x -= normal.x * impulse
        badges[left].velocity.y -= normal.y * impulse
        badges[right].velocity.x += normal.x * impulse
        badges[right].velocity.y += normal.y * impulse
    }
}

private struct BadgeCircle: View {
    let badge: PhysicsBadge

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: badge.colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: badge.systemName)
                .font(.system(size: badge.radius * 0.62, weight: .black))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: badge.radius * 2, height: badge.radius * 2)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: badge.colors.first?.opacity(0.22) ?? .clear, radius: 14, y: 8)
    }
}

private struct PhysicsBadge: Identifiable {
    let id: Int
    let radius: CGFloat
    let systemName: String
    let colors: [Color]
    var position: CGPoint = .zero
    var velocity: CGPoint = .zero

    static let samples: [PhysicsBadge] = [
        .init(id: 1, radius: 34, systemName: "music.note", colors: [.pink, .red]),
        .init(id: 2, radius: 28, systemName: "star.fill", colors: [.yellow, .orange]),
        .init(id: 3, radius: 31, systemName: "bolt.fill", colors: [.cyan, .blue]),
        .init(id: 4, radius: 26, systemName: "heart.fill", colors: [.purple, .indigo]),
        .init(id: 5, radius: 30, systemName: "waveform", colors: [.mint, .green]),
        .init(id: 6, radius: 27, systemName: "sparkles", colors: [.orange, .red])
    ]
}

private final class MotionGravityObserver: ObservableObject {
    @Published var gravity = CMAcceleration(x: 0, y: -0.75, z: 0)

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            self?.gravity = motion.gravity
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

private final class ShakeMotionObserver: ObservableObject {
    @Published var shakeCount = 0

    private let manager = CMMotionManager()
    private var lastShakeDate = Date.distantPast
    private var lastMagnitude = 1.0

    func start() {
        guard manager.isAccelerometerAvailable else { return }
        manager.accelerometerUpdateInterval = 1.0 / 30.0
        manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.handleAcceleration(data.acceleration)
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
    }

    private func handleAcceleration(_ acceleration: CMAcceleration) {
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        let impulse = abs(magnitude - lastMagnitude)
        lastMagnitude = magnitude

        guard magnitude > 2.25 || impulse > 1.35 else { return }
        guard Date().timeIntervalSince(lastShakeDate) > 1.2 else { return }
        lastShakeDate = Date()
        shakeCount += 1
    }
}

private struct BottomNavigationBar: View {
    @Binding var activeTab: AppTab
    let nowPlaying: DemoSong
    let isPlaying: Bool
    let namespace: Namespace.ID
    let isPlayerCardVisible: Bool
    @Binding var playerPillFrame: CGRect
    let onPlayerTap: () -> Void
    let onTogglePlayback: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CircleActionButton(systemName: "house.fill", isActive: activeTab == .home) {
                activeTab = .home
            }

            PlayerPill(
                song: nowPlaying,
                isPlaying: isPlaying,
                isActive: activeTab == .player,
                namespace: namespace,
                isPlayerCardVisible: isPlayerCardVisible,
                playerPillFrame: $playerPillFrame,
                action: onPlayerTap,
                onTogglePlayback: onTogglePlayback
            )

            CircleActionButton(systemName: "person.fill", isActive: activeTab == .settings) {
                activeTab = .settings
            }
        }
        .frame(maxWidth: 340)
    }
}

private struct ExpandedPlayerCard: View {
    let songs: [DemoSong]
    @Binding var nowPlaying: DemoSong
    let namespace: Namespace.ID
    let cornerRadius: CGFloat
    let surfaceOpacity: Double
    let isContentVisible: Bool
    let isPlaybackActive: (DemoSong) -> Bool
    let onClose: () -> Void
    let onSongChange: (DemoSong) -> Void
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var pendingSongChangeTask: Task<Void, Never>?
    private let cardSpacing: CGFloat = 10

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                let pageHeight = max(proxy.size.height - 42, 520)
                let pageStride = pageHeight + cardSpacing

                ZStack(alignment: .top) {
                    if let previousSong {
                        AdjacentPlayerPreviewCard(song: previousSong)
                            .frame(height: pageHeight)
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            }
                            .offset(y: -pageStride + dragOffset)
                            .allowsHitTesting(false)
                    }

                    if let song = currentSong {
                        NowPlayingCard(
                            song: song,
                            isActive: true,
                            isPlaying: isPlaybackActive(song),
                            onClose: onClose,
                            onTogglePlayback: {
                                onSongChange(song)
                            }
                        )
                        .frame(height: pageHeight)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        }
                        .offset(y: dragOffset)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 8, coordinateSpace: .local)
                                .onChanged { value in
                                    guard isContentVisible else { return }
                                    dragOffset = boundedDragOffset(value.translation.height, pageHeight: pageHeight)
                                }
                                .onEnded { value in
                                    guard isContentVisible else { return }
                                    finishDrag(value, pageHeight: pageHeight)
                                }
                            )
                    }

                    if let nextSong {
                        AdjacentPlayerPreviewCard(song: nextSong)
                            .frame(height: pageHeight)
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            }
                            .offset(y: pageStride + dragOffset)
                            .allowsHitTesting(false)
                    }
                }
            }
            .opacity(isContentVisible ? 1 : 0)
            .scaleEffect(isContentVisible ? 1 : 0.98)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .onAppear {
            currentIndex = indexForNowPlaying()
        }
        .onChange(of: nowPlaying.id) { _, newID in
            guard let newIndex = songs.firstIndex(where: { $0.id == newID }) else { return }
            guard newIndex != currentIndex else { return }
            currentIndex = newIndex
            dragOffset = 0
        }
        .onChange(of: songs.map(\.id)) { _, _ in
            let newIndex = min(indexForNowPlaying(), max(songs.count - 1, 0))
            currentIndex = newIndex
            dragOffset = 0
        }
        .onDisappear {
            pendingSongChangeTask?.cancel()
        }
    }

    private func indexForNowPlaying() -> Int {
        songs.firstIndex(where: { $0.id == nowPlaying.id }) ?? 0
    }

    private var currentSong: DemoSong? {
        guard songs.indices.contains(currentIndex) else { return nil }
        return songs[currentIndex]
    }

    private var previousSong: DemoSong? {
        let index = currentIndex - 1
        guard songs.indices.contains(index) else { return nil }
        return songs[index]
    }

    private var nextSong: DemoSong? {
        let index = currentIndex + 1
        guard songs.indices.contains(index) else { return nil }
        return songs[index]
    }

    private func boundedDragOffset(_ offset: CGFloat, pageHeight: CGFloat) -> CGFloat {
        let pageStride = pageHeight + cardSpacing
        if currentIndex == 0 && offset > 0 {
            return offset * 0.18
        }
        if currentIndex == songs.count - 1 && offset < 0 {
            return offset * 0.18
        }
        return max(min(offset, pageStride), -pageStride)
    }

    private func finishDrag(_ value: DragGesture.Value, pageHeight: CGFloat) {
        let threshold = pageHeight * 0.16
        let predicted = value.predictedEndTranslation.height
        var nextIndex = currentIndex

        if (value.translation.height < -threshold || predicted < -pageHeight * 0.30), currentIndex < songs.count - 1 {
            nextIndex += 1
        } else if (value.translation.height > threshold || predicted > pageHeight * 0.30), currentIndex > 0 {
            nextIndex -= 1
        }

        if nextIndex == currentIndex {
            withAnimation(.smooth(duration: 0.18, extraBounce: 0.0)) {
                dragOffset = 0
            }
            return
        }

        let song = songs[nextIndex]
        let pageStride = pageHeight + cardSpacing
        let exitOffset = nextIndex > currentIndex ? -pageStride : pageStride
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.12)) {
            dragOffset = exitOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            currentIndex = nextIndex
            nowPlaying = song
            dragOffset = -exitOffset * 0.10
            withAnimation(.smooth(duration: 0.16, extraBounce: 0.0)) {
                dragOffset = 0
            }
        }
        schedulePlayback(for: song)
    }

    private func schedulePlayback(for song: DemoSong) {
        pendingSongChangeTask?.cancel()
        pendingSongChangeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(620))
            guard !Task.isCancelled else { return }
            onSongChange(song)
        }
    }
}

private struct NowPlayingCard: View {
    let song: DemoSong
    let isActive: Bool
    let isPlaying: Bool
    let onClose: () -> Void
    let onTogglePlayback: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, 220)

            ZStack(alignment: .topLeading) {
                PlayerUnifiedCardBackground(song: song, coverHeight: side)

                VStack(alignment: .leading, spacing: 18) {
                    PlayerCoverArtwork(song: song)
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(song.title)
                            .font(.system(size: 34, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.66)

                        Text(song.artist)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTogglePlayback()
            }
            .overlay {
                if !isPlaying {
                    Color.black.opacity(0.18)
                        .allowsHitTesting(false)
                        .transition(.opacity)

                    RoundedPlayTriangle(cornerRadius: 10)
                        .fill(.white.opacity(0.60))
                        .frame(width: 54, height: 62)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: isPlaying)
            .overlay(alignment: .topTrailing) {
                closeButton
                    .padding(14)
            }
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.34))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct RoundedPlayTriangle: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]

        var path = Path()
        let radius = max(0, min(cornerRadius, min(rect.width, rect.height) * 0.12))

        func point(from start: CGPoint, to end: CGPoint, distance: CGFloat) -> CGPoint {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = max(sqrt(dx * dx + dy * dy), 0.001)
            return CGPoint(x: start.x + dx / length * distance, y: start.y + dy / length * distance)
        }

        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let start = point(from: current, to: previous, distance: radius)
            let end = point(from: current, to: next, distance: radius)

            if index == 0 {
                path.move(to: start)
            } else {
                path.addLine(to: start)
            }
            path.addQuadCurve(to: end, control: current)
        }

        path.closeSubpath()
        return path
    }
}

private struct AdjacentPlayerPreviewCard: View {
    let song: DemoSong

    var body: some View {
        GeometryReader { proxy in
            let coverHeight = min(proxy.size.width, proxy.size.height * 0.58)

            ZStack(alignment: .bottomLeading) {
                song.magicColor
                    .opacity(0.92)

                if let image = song.artworkImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: coverHeight)
                        .clipped()
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                LinearGradient(
                    colors: [
                        .black.opacity(0.0),
                        .black.opacity(0.42),
                        .black.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(song.title)
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)

                    Text(song.artist)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
                .padding(24)
            }
        }
    }
}

private struct PlayerUnifiedCardBackground: View {
    let song: DemoSong
    let coverHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let fadeStart = min(max((coverHeight - 360) / height, 0.05), 0.58)
            let fadeMid = min(max((coverHeight - 100) / height, fadeStart + 0.14), 0.76)
            let fadeEnd = min(max((coverHeight + 260) / height, fadeMid + 0.18), 0.96)

            ZStack {
                Color.black

                if let backdropImage = song.backdropImage {
                    Image(uiImage: backdropImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(0.72)
                        .clipped()
                } else {
                    LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                }

                song.magicColor
                    .opacity(0.24)

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.10), location: 0.0),
                        .init(color: .black.opacity(0.00), location: fadeStart),
                        .init(color: song.magicColor.opacity(0.18), location: fadeMid),
                        .init(color: song.magicColor.opacity(0.30), location: fadeEnd),
                        .init(color: song.magicColor.opacity(0.24), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: fadeStart),
                        .init(color: .black.opacity(0.10), location: fadeMid),
                        .init(color: .black.opacity(0.26), location: fadeEnd),
                        .init(color: .black.opacity(0.48), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

private struct PlayerCoverArtwork: View {
    let song: DemoSong

    var body: some View {
        ZStack {
            LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            if let artworkImage = song.artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.42),
                    .init(color: song.magicColor.opacity(0.06), location: 0.62),
                    .init(color: song.magicColor.opacity(0.16), location: 0.82),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.54),
                    .init(color: .black.opacity(0.72), location: 0.72),
                    .init(color: .black.opacity(0.28), location: 0.90),
                    .init(color: .black.opacity(0.0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipped()
    }
}

private struct UpNextCard: View {
    let song: DemoSong

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("接下来")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))

            Spacer(minLength: 0)

            PlayerCoverArtwork(song: song)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text(song.title)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(song.artist)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(24)
    }
}


private struct CircleActionButton: View {
    let systemName: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 29, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isActive ? Color(red: 1.0, green: 0.18, blue: 0.35) : .white.opacity(0.92))
                .frame(width: 53, height: 53)
                .background(.black.opacity(0.74))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .liquidGlassSurface(cornerRadius: 27, isInteractive: true)
    }
}

private struct PlayerPill: View {
    let song: DemoSong
    let isPlaying: Bool
    let isActive: Bool
    let namespace: Namespace.ID
    let isPlayerCardVisible: Bool
    @Binding var playerPillFrame: CGRect
    let action: () -> Void
    let onTogglePlayback: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(.black.opacity(0.74))

            HStack(spacing: 10) {
                RotatingAlbumArt(song: song, isSpinning: isPlaying)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(song.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: action)

                Spacer(minLength: 8)

                Button(action: onTogglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 38)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 11)
            .padding(.trailing, 12)
            .opacity(isPlayerCardVisible ? 0 : 1)
        }
        .frame(height: 53)
        .clipShape(RoundedRectangle(cornerRadius: 27))
        .overlay {
            RoundedRectangle(cornerRadius: 27)
                .stroke(.white.opacity(isActive ? 0.20 : 0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 27))
        .onTapGesture(perform: action)
        .liquidGlassSurface(cornerRadius: 27, isInteractive: true)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: PlayerPillFramePreferenceKey.self, value: proxy.frame(in: .global))
            }
        }
        .onPreferenceChange(PlayerPillFramePreferenceKey.self) { frame in
            playerPillFrame = frame
        }
        .opacity(isPlayerCardVisible ? 0 : 1)
    }
}

private struct PlayerPillFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct RotatingAlbumArt: View {
    let song: DemoSong
    let isSpinning: Bool
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            if let artworkImage = song.artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }

            Circle()
                .fill(.black.opacity(0.20))
                .frame(width: 9, height: 9)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.38), lineWidth: 1)
                }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .rotationEffect(.degrees(rotation))
        .id(song.id)
        .onAppear {
            updateRotation()
        }
        .onChange(of: isSpinning) { _, _ in
            updateRotation()
        }
        .onChange(of: song.id) { _, _ in
            rotation = 0
            updateRotation()
        }
    }

    private func updateRotation() {
        if isSpinning {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                rotation = 0
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat, isInteractive: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if isInteractive {
                self.glassEffect(.regular.tint(.white.opacity(0.14)).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular.tint(.white.opacity(0.10)), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
    }
}

private extension UIImage {
    var playerBackdropImage: UIImage? {
        let targetSize = CGSize(width: 44, height: 88)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            let fillRect = AVMakeRect(aspectRatio: size, insideRect: CGRect(origin: .zero, size: targetSize))
            let scale = max(targetSize.width / fillRect.width, targetSize.height / fillRect.height)
            let drawSize = CGSize(width: fillRect.width * scale, height: fillRect.height * scale)
            let drawRect = CGRect(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            draw(in: drawRect)
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: targetSize))
        }
    }

    var magicAverageColor: UIColor? {
        let size = CGSize(width: 12, height: 12)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: Int(size.width * size.height) * 4)

        guard let context = CGContext(
            data: &pixels,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        UIGraphicsPushContext(context)
        draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var weightTotal: CGFloat = 0

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[index]) / 255
            let g = CGFloat(pixels[index + 1]) / 255
            let b = CGFloat(pixels[index + 2]) / 255
            let brightness = max(r, g, b)
            let saturation = brightness == 0 ? 0 : (brightness - min(r, g, b)) / brightness
            let weight = max(0.18, saturation) * max(0.22, min(brightness, 0.92))

            red += r * weight
            green += g * weight
            blue += b * weight
            weightTotal += weight
        }

        guard weightTotal > 0 else { return nil }
        return UIColor(
            red: min(red / weightTotal * 1.16, 1),
            green: min(green / weightTotal * 1.16, 1),
            blue: min(blue / weightTotal * 1.16, 1),
            alpha: 1
        )
    }
}

private extension UIColor {
    convenience init(songPalette colors: [Color]) {
        let resolved = colors.first?.resolve(in: EnvironmentValues()) ?? Color.Resolved(red: 0.12, green: 0.12, blue: 0.14)
        self.init(
            red: CGFloat(resolved.red),
            green: CGFloat(resolved.green),
            blue: CGFloat(resolved.blue),
            alpha: CGFloat(resolved.opacity)
        )
    }
}

private struct TopGlassFade: View {
    private let background = Color.black

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.78)
                    .mask(
                        LinearGradient(
                            colors: [
                                .black,
                                .black.opacity(0.86),
                                .black.opacity(0.58),
                                .black.opacity(0.22),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                LinearGradient(
                    colors: [
                        background,
                        background.opacity(0.94),
                        background.opacity(0.78),
                        background.opacity(0.54),
                        background.opacity(0.30),
                        background.opacity(0.12),
                        background.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        .white.opacity(0.06),
                        .white.opacity(0.018),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.screen)
            }
            .frame(height: 320)

            Spacer(minLength: 0)
        }
    }
}

private struct BottomGlassFade: View {
    private let background = Color.black

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.78)
                    .mask(
                        LinearGradient(
                            colors: [
                                .clear,
                                .black.opacity(0.22),
                                .black.opacity(0.58),
                                .black.opacity(0.86),
                                .black
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                LinearGradient(
                    colors: [
                        background.opacity(0.0),
                        background.opacity(0.12),
                        background.opacity(0.30),
                        background.opacity(0.54),
                        background.opacity(0.78),
                        background.opacity(0.94),
                        background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.018),
                        .white.opacity(0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.screen)
            }
            .frame(height: 220)
        }
    }
}

private struct DemoSong: Identifiable {
    let id: Int
    let title: String
    let artist: String
    let colors: [Color]
    let mediaItem: MPMediaItem?
    let artworkImage: UIImage?
    let backdropImage: UIImage?
    let magicColor: Color

    init(
        id: Int,
        title: String,
        artist: String,
        colors: [Color],
        mediaItem: MPMediaItem? = nil,
        artworkImage: UIImage? = nil,
        backdropImage: UIImage? = nil,
        magicColor: Color? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.colors = colors
        self.mediaItem = mediaItem
        self.artworkImage = artworkImage
        self.backdropImage = backdropImage
        self.magicColor = magicColor ?? colors.first ?? .black
    }

    static let library: [DemoSong] = [
        .init(id: 1, title: "DESIRE", artist: "Calvin Harris", colors: [.red, .orange]),
        .init(id: 2, title: "Anti-Hero", artist: "Taylor Swift", colors: [.indigo, .cyan]),
        .init(id: 3, title: "One Kiss", artist: "Dua Lipa", colors: [.purple, .blue]),
        .init(id: 4, title: "greedy", artist: "Tate McRae", colors: [.green, .mint]),
        .init(id: 5, title: "Miracle", artist: "Ellie Goulding", colors: [.pink, .yellow]),
        .init(id: 6, title: "Paint The Town Red", artist: "Doja Cat", colors: [.black, .red]),
        .init(id: 7, title: "Rush", artist: "Troye Sivan", colors: [.teal, .blue]),
        .init(id: 8, title: "Dance The Night", artist: "Dua Lipa", colors: [.orange, .pink]),
        .init(id: 9, title: "Ocean Eyes", artist: "Billie Eilish", colors: [.blue, .gray]),
        .init(id: 10, title: "Golden Hour", artist: "JVKE", colors: [.yellow, .orange]),
        .init(id: 11, title: "As It Was", artist: "Harry Styles", colors: [.mint, .cyan]),
        .init(id: 12, title: "Save Your Tears", artist: "The Weeknd", colors: [.purple, .red]),
        .init(id: 13, title: "Flowers", artist: "Miley Cyrus", colors: [.pink, .red]),
        .init(id: 14, title: "Levitating", artist: "Dua Lipa", colors: [.blue, .purple]),
        .init(id: 15, title: "Blinding Lights", artist: "The Weeknd", colors: [.red, .yellow]),
        .init(id: 16, title: "Bad Guy", artist: "Billie Eilish", colors: [.green, .black]),
        .init(id: 17, title: "Cruel Summer", artist: "Taylor Swift", colors: [.orange, .red]),
        .init(id: 18, title: "Heat Waves", artist: "Glass Animals", colors: [.yellow, .pink]),
        .init(id: 19, title: "Peaches", artist: "Justin Bieber", colors: [.orange, .mint]),
        .init(id: 20, title: "Stay", artist: "The Kid LAROI", colors: [.cyan, .blue]),
        .init(id: 21, title: "Watermelon Sugar", artist: "Harry Styles", colors: [.pink, .green]),
        .init(id: 22, title: "Houdini", artist: "Dua Lipa", colors: [.purple, .orange]),
        .init(id: 23, title: "vampire", artist: "Olivia Rodrigo", colors: [.black, .purple]),
        .init(id: 24, title: "Espresso", artist: "Sabrina Carpenter", colors: [.brown, .orange]),
        .init(id: 25, title: "Birds Of A Feather", artist: "Billie Eilish", colors: [.cyan, .mint]),
        .init(id: 26, title: "Fortnight", artist: "Taylor Swift", colors: [.gray, .black]),
        .init(id: 27, title: "Training Season", artist: "Dua Lipa", colors: [.blue, .pink]),
        .init(id: 28, title: "Illusion", artist: "Dua Lipa", colors: [.teal, .purple]),
        .init(id: 29, title: "Chemical", artist: "Post Malone", colors: [.yellow, .green]),
        .init(id: 30, title: "Sunroof", artist: "Nicky Youre", colors: [.orange, .cyan]),
        .init(id: 31, title: "Easy On Me", artist: "Adele", colors: [.indigo, .gray]),
        .init(id: 32, title: "Shivers", artist: "Ed Sheeran", colors: [.red, .pink]),
        .init(id: 33, title: "Nonsense", artist: "Sabrina Carpenter", colors: [.mint, .purple]),
        .init(id: 34, title: "Late Night Talking", artist: "Harry Styles", colors: [.orange, .blue]),
        .init(id: 35, title: "Lavender Haze", artist: "Taylor Swift", colors: [.purple, .indigo]),
        .init(id: 36, title: "About Damn Time", artist: "Lizzo", colors: [.yellow, .pink]),
        .init(id: 37, title: "Karma", artist: "Taylor Swift", colors: [.cyan, .indigo]),
        .init(id: 38, title: "Woman", artist: "Doja Cat", colors: [.red, .purple]),
        .init(id: 39, title: "Snap", artist: "Rosa Linn", colors: [.mint, .blue]),
        .init(id: 40, title: "abcdefu", artist: "GAYLE", colors: [.black, .pink])
    ]
}

private struct SongSquare: View {
    let song: DemoSong
    let isPlaying: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

                if let artworkImage = song.artworkImage {
                    Image(uiImage: artworkImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
                        .clipped()
                }

                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 58, height: 58)
                    .offset(x: side * 0.36, y: -side * 0.34)

            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isPlaying ? .white.opacity(0.82) : .clear, lineWidth: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct HomeFlipSongSquare: View {
    let frontSong: DemoSong
    let backSong: DemoSong
    let isPlaying: Bool
    let progress: CGFloat
    let variation: HomeFlipVariation

    var body: some View {
        ZStack {
            if progress < 0.5 {
                SongSquare(song: frontSong, isPlaying: isPlaying)
            } else {
                SongSquare(song: backSong, isPlaying: isPlaying)
                    .rotation3DEffect(
                        .degrees(180),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.72
                    )
            }
        }
        .rotation3DEffect(
            .degrees(flipRotation),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: 0.72
        )
        .rotationEffect(.degrees(variation.tilt * sin(Double(progress) * .pi)))
        .offset(y: variation.lift * sin(CGFloat(progress) * .pi))
    }

    private var flipRotation: Double {
        Double(progress * 180)
    }
}

#Preview {
    ContentView()
}
