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
import Network

struct ContentView: View {
    @State private var activeTab: AppTab = .home
    @State private var nowPlaying = DemoSong.library[0]
    @StateObject private var musicConnector = MusicConnectionManager()
    @State private var isPlayerCardVisible = false
    @State private var isPlayerCardExpanded = false
    @State private var isPlayerCardContentVisible = false
    @State private var isPlayerPillHiddenForExpansion = false
    @State private var isPlayerCardDismissing = false
    @State private var playerMorphProgress: CGFloat = 0
    @State private var playerPillFrame: CGRect = .zero
    @State private var homeDriftAmount: CGFloat = 0
    @State private var homeSongs: [DemoSong] = []
    @State private var homePendingSongs: [DemoSong] = []
    @State private var homeFlipProgressByID: [Int: CGFloat] = [:]
    @State private var homeFlipVariations: [Int: HomeFlipVariation] = [:]
    @State private var isHomeFlipping = false
    @State private var homeFlipGeneration = UUID()
    @State private var isHomeLoadingMore = false
    @State private var isHomeAppendingMore = false
    @State private var homeLoadMorePage = 0
    @State private var temporarilySkippedHomeSongIDs: [Int] = []
    @State private var pendingHomePlaybackTask: Task<Void, Never>?
    @StateObject private var shakeObserver = ShakeMotionObserver()
    @State private var homeIdleTask: Task<Void, Never>?
    @State private var homeFlipTask: Task<Void, Never>?
    @Namespace private var playerExpansionNamespace

    private let spacing: CGFloat = 8
    private var songs: [DemoSong] {
        musicConnector.discoverySongs.isEmpty ? DemoSong.library : musicConnector.discoverySongs
    }
    private var visibleHomeSongs: [DemoSong] {
        homeSongs.isEmpty ? songs : homeSongs
    }
    private var settingsBackdropBlur: CGFloat {
        activeTab == .settings ? 16 : 0
    }
    private var playerBackdropBlur: CGFloat {
        isPlayerCardVisible ? 18 : 0
    }
    private var isPlaybackVisuallyActive: Bool {
        musicConnector.isPlaying || musicConnector.isPlaybackTransitioning
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            let homeColumnCount = isLandscape ? 5 : 4
            let chromeOpacity = isLandscape ? 0.0 : 1.0

            ZStack {
            Color(red: 0.0, green: 0.027, blue: 0.098)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(0..<homeColumnCount), id: \.self) { column in
                        LazyVStack(spacing: spacing) {
                            ForEach(songSlotsForColumn(column, columnCount: homeColumnCount)) { slot in
                                HomeInteractiveSongSquare(
                                    frontSong: visibleHomeSongs[slot.id],
                                    backSong: homePendingSongs.indices.contains(slot.id) ? homePendingSongs[slot.id] : visibleHomeSongs[slot.id],
                                    displayedSong: slot.song,
                                    isPlaying: slot.song.id == nowPlaying.id,
                                    progress: homeFlipLocalProgress(for: slot),
                                    variation: homeFlipVariations[slot.id] ?? .zero,
                                    onTap: {
                                        playHomeSong(slot.song)
                                    }
                                )
                                .onAppear {
                                    loadMoreHomeSongsIfNeeded(slot)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, isLandscape ? 0 : topOffset(for: column))
                        .offset(y: homeDriftOffset(for: column))
                    }
                }
                .padding(.horizontal, isLandscape ? 0 : spacing)
                .padding(.top, isLandscape ? 0 : spacing)
                .padding(.bottom, isLandscape ? spacing : 92)
            }
            .ignoresSafeArea(edges: isLandscape ? .all : [])
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        registerHomeInteraction()
                    }
            )
            .blur(radius: settingsBackdropBlur + playerBackdropBlur, opaque: false)
            .scaleEffect(activeTab == .settings ? 0.985 : (isPlayerCardVisible ? 0.985 : 1))
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: activeTab)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: isPlayerCardVisible)
            .zIndex(0)

            TopGlassFade()
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .blur(radius: settingsBackdropBlur + playerBackdropBlur, opaque: false)
                .opacity(chromeOpacity)
                .zIndex(1)

            BottomGlassFade()
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .blur(radius: settingsBackdropBlur + playerBackdropBlur, opaque: false)
                .opacity(chromeOpacity)
                .zIndex(1)

            if isPlaybackVisuallyActive {
                MusicSparkleField(song: nowPlaying)
                    .frame(width: proxy.size.width, height: min(proxy.size.height * 0.56, 520))
                    .offset(y: 74)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .blur(radius: settingsBackdropBlur + playerBackdropBlur, opaque: false)
                .transition(.opacity.animation(.easeOut(duration: 0.22)))
                .zIndex(4)
            }

            VStack {
                HStack(alignment: .top) {
                    if musicConnector.isPlaying {
                        HeaderNowPlayingBadge(song: nowPlaying)
                    } else {
                        GreetingBadge()
                    }
                    Spacer()
                    TopSettingsButton {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        activeTab = .settings
                    }
                    .opacity(chromeOpacity)
                    .allowsHitTesting(!isLandscape)
                }
                .padding(.leading, 20)
                .padding(.trailing, 14)
                .padding(.top, 12)
                .offset(y: 10)

                Spacer()
            }
            .blur(radius: settingsBackdropBlur + playerBackdropBlur, opaque: false)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: activeTab)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: isPlayerCardVisible)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: isLandscape)
            .zIndex(6)

            VStack {
                Spacer()
                BottomNavigationBar(
                    nowPlaying: nowPlaying,
                    isPlaying: musicConnector.isPlaying,
                    isPlaybackLoading: musicConnector.isPlaybackTransitioning,
                    namespace: playerExpansionNamespace,
                    isPlayerCardVisible: isPlayerCardVisible,
                    isDropTargeted: false,
                    playerPillFrame: $playerPillFrame,
                    onPlayerTap: toggleCurrentPlayback,
                    onTogglePlayback: toggleCurrentPlayback,
                    onPrevious: {
                        playAdjacentSong(step: -1)
                    },
                    onNext: {
                        playAdjacentSong(step: 1)
                    }
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .blur(radius: settingsBackdropBlur + playerBackdropBlur, opaque: false)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: activeTab)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: isPlayerCardVisible)
            .zIndex(8)

            if activeTab == .settings {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .zIndex(11)
                    .onTapGesture {
                        withAnimation(.smooth(duration: 0.24, extraBounce: 0.0)) {
                            activeTab = .home
                        }
                    }

                SettingsModalView(connector: musicConnector) {
                    withAnimation(.smooth(duration: 0.24, extraBounce: 0.0)) {
                        activeTab = .home
                    }
                }
                .padding(.horizontal, 12)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
                .zIndex(12)
            }
        }
        .coordinateSpace(name: "contentRoot")
        }
        .task {
            await musicConnector.refreshAppleMusicLibraryIfPossible()
        }
        .onAppear {
            musicConnector.startPlaybackSync()
            syncHomeSongsIfNeeded()
            shakeObserver.start()
            scheduleHomeIdleDrift()
        }
        .onDisappear {
            musicConnector.stopPlaybackSync()
            pendingHomePlaybackTask?.cancel()
            pendingHomePlaybackTask = nil
            resetHomeFlipState()
            stopHomeDrift()
            shakeObserver.stop()
        }
        .onReceive(musicConnector.$currentSong.compactMap { $0 }) { song in
            guard song.id != nowPlaying.id else { return }
            nowPlaying = song
            if isPlayerCardVisible {
                musicConnector.loadLyricsIfNeeded(for: song)
            }
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
            } else if isHomeSurfaceVisible {
                scheduleHomeIdleDrift()
            }
        }
        .onChange(of: songs.map(\.id)) { _, _ in
            guard isHomeAppendingMore == false else { return }
            syncHomeSongsIfNeeded(force: true)
        }
        .onReceive(shakeObserver.$shakeEventID.dropFirst()) { _ in
            reshuffleHomeSongsWithFlip()
        }
    }

    private func playHomeSong(_ song: DemoSong) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        registerHomeInteraction()

        guard song.isPlayable, song.isPlaceholder == false else {
            musicConnector.message = "这首暂时没有可播放资源。"
            return
        }

        pendingHomePlaybackTask?.cancel()
        let queueSnapshot = compactHomePlaybackSnapshot(startingWith: song)
        pendingHomePlaybackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(72))
            guard !Task.isCancelled else { return }
            nowPlaying = song
            musicConnector.queuePlayback(for: song, in: queueSnapshot)
        }
    }

    private func compactHomePlaybackSnapshot(startingWith song: DemoSong) -> [DemoSong] {
        let playableSongs = visibleHomeSongs.filter { $0.isPlayable && $0.isPlaceholder == false }
        guard playableSongs.isEmpty == false else { return [song] }
        guard let selectedIndex = playableSongs.firstIndex(where: { $0.id == song.id }) else {
            return Array(([song] + playableSongs).prefix(5))
        }
        let rotatedSongs = Array(playableSongs[selectedIndex...]) + Array(playableSongs[..<selectedIndex])
        return Array(rotatedSongs.prefix(5))
    }

    private func toggleCurrentPlayback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let playbackSongs = songs
        Task { await musicConnector.togglePlayback(for: nowPlaying, in: playbackSongs) }
    }

    private func playAdjacentSong(step: Int) {
        let playbackSongs = songs
        guard let song = adjacentPlayableSong(step: step, in: playbackSongs) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        nowPlaying = song
        musicConnector.queuePlayback(for: song, in: playbackSongs)
    }

    private func adjacentPlayableSong(step: Int, in playbackSongs: [DemoSong]) -> DemoSong? {
        guard playbackSongs.isEmpty == false, step != 0 else { return nil }
        let startIndex = playbackSongs.firstIndex(where: { $0.id == nowPlaying.id }) ?? 0
        for distance in 1...playbackSongs.count {
            let rawIndex = startIndex + step * distance
            let index = (rawIndex % playbackSongs.count + playbackSongs.count) % playbackSongs.count
            let candidate = playbackSongs[index]
            if candidate.id != nowPlaying.id, candidate.isPlayable {
                return candidate
            }
        }
        return nil
    }

    private func showPlayerCard() {
        guard !isPlayerCardVisible else { return }
        stopHomeDrift()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        activeTab = .player
        isPlayerCardContentVisible = false
        isPlayerCardDismissing = false
        isPlayerCardVisible = true
        musicConnector.loadLyricsIfNeeded(for: nowPlaying)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            guard isPlayerCardVisible else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                isPlayerCardContentVisible = true
            }
        }
    }

    private func hidePlayerCard() {
        guard isPlayerCardVisible else { return }

        withAnimation(.easeOut(duration: 0.12)) {
            isPlayerCardDismissing = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isPlayerCardVisible = false
            isPlayerCardContentVisible = false
            isPlayerCardDismissing = false
            activeTab = .home
        }
    }

    private func songsForColumn(_ column: Int, columnCount: Int = 4) -> [DemoSong] {
        visibleHomeSongs.enumerated().compactMap { index, song in
            index % columnCount == column ? song : nil
        }
    }

    private func songSlotsForColumn(_ column: Int, columnCount: Int = 4) -> [HomeSongSlot] {
        visibleHomeSongs.indices.compactMap { index in
            guard index % columnCount == column else { return nil }
            return HomeSongSlot(
                id: index,
                row: index / columnCount,
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
        guard isHomeFlipping else { return 0 }
        return min(max(homeFlipProgressByID[slot.id] ?? 0, 0), 1)
    }

    private func syncHomeSongsIfNeeded(force: Bool = false) {
        let currentIDs = homeSongs.map(\.id)
        let sourceIDs = songs.map(\.id)
        if force || currentIDs.sorted() != sourceIDs.sorted() {
            homeSongs = initialHomeSongs()
            resetHomeFlipState()
        }
    }

    private func loadMoreHomeSongsIfNeeded(_ slot: HomeSongSlot) {
        guard isHomeSurfaceVisible else { return }
        guard isHomeLoadingMore == false else { return }
        guard visibleHomeSongs.count >= 24 else { return }
        guard slot.id >= max(visibleHomeSongs.count - 10, 0) else { return }

        isHomeLoadingMore = true
        isHomeAppendingMore = true
        let page = homeLoadMorePage
        homeLoadMorePage += 1

        Task { @MainActor in
            let additions = await musicConnector.loadMoreDiscoverySongs(page: page)
            guard Task.isCancelled == false else { return }
            appendLoadedHomeSongs(additions)
        }
    }

    private func appendLoadedHomeSongs(_ additions: [DemoSong]) {
        guard additions.isEmpty == false else {
            isHomeLoadingMore = false
            isHomeAppendingMore = false
            return
        }

        let current = homeSongs.isEmpty ? songs : homeSongs
        let startIndex = current.count
        let targetSongs = current + additions
        homeSongs = targetSongs
        homePendingSongs = targetSongs
        homeFlipVariations = makeHomeFlipVariations(count: targetSongs.count)

        var progress = Dictionary(uniqueKeysWithValues: targetSongs.indices.map { ($0, CGFloat(1)) })
        for index in startIndex..<targetSongs.count {
            progress[index] = 0
        }
        homeFlipProgressByID = progress

        let generation = UUID()
        homeFlipGeneration = generation
        isHomeFlipping = true

        homeFlipTask = Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            for index in startIndex..<targetSongs.count {
                let row = index / 4
                let column = index % 4
                let stagger = (row - startIndex / 4) * 76 + [38, 8, 58, 22][column] + Int.random(in: 0...60)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(max(0, stagger)))
                    guard !Task.isCancelled, isHomeFlipping, homeFlipGeneration == generation else { return }
                    generator.impactOccurred(intensity: 0.28)
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.02)) {
                        homeFlipProgressByID[index] = 1
                    }
                }
            }

            let rows = max(1, Int(ceil(Double(additions.count) / 4.0)))
            try? await Task.sleep(for: .milliseconds(rows * 82 + 520))
            guard !Task.isCancelled, homeFlipGeneration == generation else { return }
            resetHomeFlipState()
            isHomeLoadingMore = false
            isHomeAppendingMore = false
        }
    }

    private func reshuffleHomeSongsWithFlip() {
        guard isHomeSurfaceVisible, songs.count > 1 else { return }
        registerHomeInteraction()
        resetHomeFlipState()
        rememberTemporarilySkippedHomeSongs(visibleHomeSongs.prefix(48).map(\.id))

        let nextSongs = reshuffledHomeSongs()
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
            guard !Task.isCancelled, homeFlipGeneration == generation else { return }
            homeSongs = nextSongs
            resetHomeFlipState()
        }
    }

    private func resetHomeFlipState() {
        homeFlipTask?.cancel()
        homeFlipTask = nil
        homeFlipGeneration = UUID()
        homePendingSongs = []
        homeFlipVariations = [:]
        homeFlipProgressByID = [:]
        isHomeFlipping = false
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

    private func initialHomeSongs() -> [DemoSong] {
        timeMatchedHomeSongs(from: songs, avoiding: temporarilySkippedHomeSongIDsSet(), excludingCurrentFront: false)
    }

    private func reshuffledHomeSongs() -> [DemoSong] {
        timeMatchedHomeSongs(from: songs, avoiding: temporarilySkippedHomeSongIDsSet(), excludingCurrentFront: true)
    }

    private func timeMatchedHomeSongs(
        from source: [DemoSong],
        avoiding rejectedIDs: Set<Int>,
        excludingCurrentFront: Bool
    ) -> [DemoSong] {
        let currentFrontIDs = Set(visibleHomeSongs.prefix(48).map(\.id))
        let mood = HomeTimeMood.current
        let freshSongs = source.filter { song in
            rejectedIDs.contains(song.id) == false &&
            (!excludingCurrentFront || currentFrontIDs.contains(song.id) == false)
        }
        let fallbackFresh = source.filter { song in
            !excludingCurrentFront || currentFrontIDs.contains(song.id) == false
        }
        let primary = freshSongs.isEmpty ? fallbackFresh : freshSongs
        let overflow = source.filter { song in primary.contains(where: { $0.id == song.id }) == false }
        let rankedPrimary = primary
            .map { song in (song, mood.score(song) + Double.random(in: 0...0.9)) }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        let rankedOverflow = overflow
            .map { song in (song, mood.score(song) + Double.random(in: 0...0.5)) }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        let result = rankedPrimary + rankedOverflow
        guard result.first?.id == visibleHomeSongs.first?.id, result.count > 1 else { return result }
        return Array(result.dropFirst()) + [result[0]]
    }

    private func temporarilySkippedHomeSongIDsSet() -> Set<Int> {
        Set(temporarilySkippedHomeSongIDs)
    }

    private func rememberTemporarilySkippedHomeSongs(_ ids: [Int]) {
        let realIDs = ids.filter { $0 > 0 }
        guard realIDs.isEmpty == false else { return }
        var stored = temporarilySkippedHomeSongIDs
        stored.append(contentsOf: realIDs)
        var seen = Set<Int>()
        let capped = stored.reversed().filter { seen.insert($0).inserted }.prefix(160).reversed()
        temporarilySkippedHomeSongIDs = Array(capped)
    }

    private func registerHomeInteraction() {
        guard isHomeSurfaceVisible else { return }
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
            guard isHomeSurfaceVisible else { return }
            var target: CGFloat = 1
            while !Task.isCancelled, isHomeSurfaceVisible {
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
        return column.isMultiple(of: 2) ? -distance : distance
    }

    private var isHomeSurfaceVisible: Bool {
        activeTab != .settings && isPlayerCardVisible == false
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

private enum HomeTimeMood {
    case morning
    case afternoon
    case evening
    case lateNight

    static var current: HomeTimeMood {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return .morning
        case 11..<17: return .afternoon
        case 17..<22: return .evening
        default: return .lateNight
        }
    }

    var greeting: String {
        switch self {
        case .morning: return "Good Morning"
        case .afternoon: return "Good Afternoon"
        case .evening: return "Good Evening"
        case .lateNight: return "Late Night"
        }
    }

    var emoji: String {
        switch self {
        case .morning: return "☕️"
        case .afternoon: return "☀️"
        case .evening: return "🌙"
        case .lateNight: return "✨"
        }
    }

    func score(_ song: DemoSong) -> Double {
        let text = "\(song.title) \(song.artist)".lowercased()
        let colorScore = song.colors.reduce(0.0) { partial, color in
            partial + colorMoodScore(color)
        } / Double(max(song.colors.count, 1))
        let keywordScore = keywordMoodScore(text)
        return colorScore + keywordScore
    }

    private func keywordMoodScore(_ text: String) -> Double {
        switch self {
        case .morning:
            return matches(text, ["morning", "sun", "gold", "easy", "sweet", "flowers", "ocean", "spring"]) * 0.95
        case .afternoon:
            return matches(text, ["dance", "rush", "heat", "hot", "training", "desire", "levitating", "light"]) * 0.95
        case .evening:
            return matches(text, ["night", "blue", "late", "dream", "moon", "cruel", "tears", "haze"]) * 0.95
        case .lateNight:
            return matches(text, ["midnight", "slow", "sleep", "bad", "eyes", "dark", "after", "alone"]) * 0.95
        }
    }

    private func matches(_ text: String, _ words: [String]) -> Double {
        words.contains { text.contains($0) } ? 1 : 0
    }

    private func colorMoodScore(_ color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        let red = Double(resolved.red)
        let green = Double(resolved.green)
        let blue = Double(resolved.blue)
        let brightness = max(red, green, blue)
        let saturation = brightness == 0 ? 0 : (brightness - min(red, green, blue)) / brightness

        switch self {
        case .morning:
            return brightness * 0.72 + (1 - saturation) * 0.18 + green * 0.22 + blue * 0.12
        case .afternoon:
            return brightness * 0.45 + saturation * 0.42 + red * 0.18 + green * 0.12
        case .evening:
            return (1 - brightness) * 0.28 + blue * 0.34 + red * 0.16 + saturation * 0.14
        case .lateNight:
            return (1 - brightness) * 0.48 + blue * 0.30 + (1 - saturation) * 0.16
        }
    }
}

private struct GreetingBadge: View {
    private let mood = HomeTimeMood.current

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let float = sin(phase * 1.6)

            HStack(alignment: .top, spacing: 8) {
                Text(mood.emoji)
                    .font(.system(size: 27, weight: .bold))
                    .scaleEffect(1 + float * 0.035)
                    .rotationEffect(.degrees(float * 3.5))
                    .offset(y: -2 + float * 2)

                Text(mood.greeting)
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            .frame(maxWidth: 310, alignment: .leading)
        }
    }
}

private struct HeaderNowPlayingBadge: View {
    let song: DemoSong

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.62)

            Text(song.artist)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: 290, alignment: .leading)
    }
}

private struct ProfilePage: View {
    @ObservedObject var connector: MusicConnectionManager
    @Binding var activeTab: AppTab

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                BadgePhysicsPanel(songs: connector.discoverySongs)
                    .frame(height: proxy.size.height * 0.42)
                    .padding(.top, proxy.safeAreaInsets.top + 18)
                    .offset(y: 10)
                    .padding(.bottom, 0)
                    .zIndex(0)
                    .allowsHitTesting(false)

                SettingsContentStack(connector: connector) {
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

                    SourceSettingsPanel(connector: connector)

                    if let message = connector.message {
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .zIndex(1)
                .padding(.horizontal, 18)
                .padding(.top, 28)

                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SettingsModalView: View {
    @ObservedObject var connector: MusicConnectionManager
    let onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let modalHeight = min(proxy.size.height * 0.86, 760)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.84))
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)

                BadgePhysicsPanel(songs: connector.discoverySongs)
                    .frame(height: modalHeight * 0.33)
                    .padding(.horizontal, 10)
                    .offset(y: 14)
                    .padding(.bottom, -2)
                    .zIndex(0)
                    .allowsHitTesting(false)

                SettingsContentStack(connector: connector) {
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
                                onClose()
                            }
                        }
                    }

                    SourceSettingsPanel(connector: connector)

                    if let message = connector.message {
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                }
                .zIndex(1)
                .padding(.horizontal, 18)
                .padding(.top, 4)

                Spacer(minLength: 18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: modalHeight)
            .background(.black.opacity(0.76))
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .liquidGlassSurface(cornerRadius: 34, isInteractive: false)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
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
    }
}

private struct SettingsContentStack<Content: View>: View {
    @ObservedObject var connector: MusicConnectionManager
    @ViewBuilder let content: Content
    @State private var lastHapticOffset: CGFloat = 0
    @State private var lastDragHapticTranslation: CGFloat = 0
    private let hapticStep: CGFloat = 10

    var body: some View {
        ScrollView(showsIndicators: false) {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: SettingsScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named("settingsContentScroll")).minY
                    )
            }
            .frame(height: 0)

            VStack(spacing: 12) {
                content
            }
            .padding(.top, 2)
            .padding(.bottom, 26)
        }
        .coordinateSpace(name: "settingsContentScroll")
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(SettingsScrollOffsetPreferenceKey.self) { offset in
            guard abs(offset - lastHapticOffset) >= hapticStep else { return }
            lastHapticOffset = offset
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.70)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    guard abs(value.translation.height - lastDragHapticTranslation) >= hapticStep else { return }
                    lastDragHapticTranslation = value.translation.height
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.58)
                }
                .onEnded { _ in
                    lastDragHapticTranslation = 0
                }
        )
    }
}

private struct SettingsScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SourceSettingsPanel: View {
    @ObservedObject var connector: MusicConnectionManager

    var body: some View {
        VStack(spacing: 10) {
            playlistMenu(
                title: "Apple Music",
                systemName: "music.note.list",
                selection: connector.selectedApplePlaylistID,
                options: connector.applePlaylistOptions
            ) { optionID in
                connector.selectApplePlaylist(optionID)
            }

            playlistMenu(
                title: "Spotify",
                systemName: "music.note",
                selection: connector.selectedSpotifyPlaylistID,
                options: connector.spotifyPlaylistOptions
            ) { optionID in
                Task { await connector.selectSpotifyPlaylist(optionID) }
            }

            Toggle(isOn: Binding(
                get: { connector.aiRecommendationsEnabled },
                set: { connector.setAIRecommendationsEnabled($0) }
            )) {
                Label("AI 歌曲推荐", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(red: 1.0, green: 0.18, blue: 0.35)))
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.black.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func playlistMenu(
        title: String,
        systemName: String,
        selection: String,
        options: [MusicPlaylistOption],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Menu {
            ForEach(options) { option in
                Button {
                    onSelect(option.id)
                } label: {
                    Label(option.title, systemImage: option.id == selection ? "checkmark" : "music.note")
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.68))

                    Text(options.first(where: { $0.id == selection })?.displayTitle ?? "全部歌单")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(.black.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MusicPlaylistOption: Identifiable, Hashable {
    static let allID = "all"

    let id: String
    let title: String
    let count: Int

    static func all(title: String, count: Int) -> MusicPlaylistOption {
        MusicPlaylistOption(id: allID, title: title, count: count)
    }

    var displayTitle: String {
        count > 0 ? "\(title) · \(count) 首" : title
    }
}

@MainActor
private final class MusicConnectionManager: ObservableObject {
    @Published var isConnectingAppleMusic = false
    @Published var isConnectingSpotify = false
    @Published var librarySongs: [DemoSong] = []
    @Published var applePlaylists: [MusicPlaylistOption] = []
    @Published var spotifySongs: [DemoSong] = []
    @Published var spotifyPlaylists: [MusicPlaylistOption] = []
    @Published var recommendedSongs: [DemoSong] = []
    @Published var discoveryExtraSongs: [DemoSong] = []
    @Published var message: String?
    @Published var currentSong: DemoSong?
    @Published var playingSongID: Int?
    @Published var isPlaying = false
    @Published var isPlaybackTransitioning = false
    @Published var showPlaybackLoadingToast = false
    @Published private var fetchedLyricsByKey: [String: String] = [:]
    @Published private var loadingLyricKeys: Set<String> = []

    @AppStorage("appleMusicConnected") private var appleMusicConnected = false
    @AppStorage("spotifyAccessToken") private var spotifyAccessToken = ""
    @AppStorage("spotifyRefreshToken") private var spotifyRefreshToken = ""
    @AppStorage("spotifyTokenExpiresAt") private var spotifyTokenExpiresAt = 0.0
    @AppStorage("selectedApplePlaylistID") var selectedApplePlaylistID = MusicPlaylistOption.allID
    @AppStorage("selectedSpotifyPlaylistID") var selectedSpotifyPlaylistID = MusicPlaylistOption.allID
    @AppStorage("aiRecommendationsEnabled") var aiRecommendationsEnabled = true

    private let spotifyAuthenticator = SpotifyPKCEAuthenticator()
    private var playbackLoadingTask: Task<Void, Never>?
    private var queuedPlaybackTask: Task<Void, Never>?
    private var playbackQueueWarmupTask: Task<Void, Never>?
    private var playbackPrefetchTask: Task<Void, Never>?
    private var recommendationTask: Task<Void, Never>?
    private var playbackObservers: [NSObjectProtocol] = []
    private var playbackRequestID = 0
    private let playbackQueueLimit = 5
    private let playbackPrefetchLimit = 8
    private let discoveryExtraSongLimit = 96
    private var nextPlaybackPrefetchPage = 1
    private var loadedPlaybackPrefetchPages = Set<Int>()

    var discoverySongs: [DemoSong] {
        let baseSongs = librarySongs.isEmpty ? DemoSong.library : librarySongs
        let recommendationSongs = aiRecommendationsEnabled ? recommendedSongs : []
        return uniqueDiscoverySongs(
            from: spotifySongs + interleavedDiscoverySongs(librarySongs: baseSongs, recommendedSongs: recommendationSongs) + discoveryExtraSongs
        )
    }

    var applePlaylistOptions: [MusicPlaylistOption] {
        [.all(title: "全部 Apple Music 歌单", count: applePlaylists.reduce(0) { $0 + $1.count })] + applePlaylists
    }

    var spotifyPlaylistOptions: [MusicPlaylistOption] {
        [.all(title: "全部 Spotify 歌单 + 已收藏", count: spotifyPlaylists.reduce(0) { $0 + $1.count })] + spotifyPlaylists
    }

    var appleMusicStatusText: String {
        appleMusicConnected ? "已连接" : "请求系统授权"
    }

    var isAppleMusicReady: Bool {
        appleMusicConnected && MPMediaLibrary.authorizationStatus() == .authorized
    }

    var spotifyStatusText: String {
        spotifyAccessToken.isEmpty ? "回调: \(SpotifyAuthConfig.redirectURI)" : "已连接"
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
        if appleMusicConnected || MPMediaLibrary.authorizationStatus() == .authorized {
            appleMusicConnected = true
            loadAppleMusicLibrary()
        } else {
            refreshRecommendations()
        }
        await refreshSpotifySongsIfPossible()
        syncPlaybackState()
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

        applePlaylists = appleMusicPlaylists()
        let items = mediaItemsFromLibrary()
        let palettes = DemoSong.library.map(\.colors)
        librarySongs = items.prefix(80).enumerated().map { index, item in
            let artworkImage = item.artwork?.image(at: CGSize(width: 220, height: 220))
            let magicColor = artworkImage?.magicAverageColor ?? UIColor(songPalette: palettes[index % palettes.count])
            return DemoSong(
                id: 10_000 + index,
                title: item.title ?? "Untitled",
                artist: item.artist ?? "Unknown Artist",
                colors: palettes[index % palettes.count],
                mediaItem: item,
                storeID: item.safePlaybackStoreID,
                artworkImage: artworkImage,
                backdropImage: artworkImage?.playerBackdropImage,
                lyricsText: Self.extractLyrics(from: item),
                magicColor: Color(uiColor: magicColor),
                source: .library
            )
        }
        message = librarySongs.isEmpty
            ? "Apple Music 已授权，但没有读到已加入资料库的歌曲。请先在 Apple Music 里把歌曲添加到资料库，并确认系统设置里允许访问媒体与 Apple Music。"
            : "已读取 \(librarySongs.count) 首歌曲"
        refreshRecommendations()
        syncPlaybackState()
    }

    func selectApplePlaylist(_ optionID: String) {
        selectedApplePlaylistID = optionID
        loadAppleMusicLibrary()
    }

    func setAIRecommendationsEnabled(_ isEnabled: Bool) {
        aiRecommendationsEnabled = isEnabled
        if isEnabled {
            refreshRecommendations()
        } else {
            recommendationTask?.cancel()
            recommendedSongs = []
            discoveryExtraSongs = []
        }
    }

    func loadMoreDiscoverySongs(page: Int) async -> [DemoSong] {
        let queries = moreDiscoveryQueries(page: page)
        let existingSongs = librarySongs + recommendedSongs + discoveryExtraSongs
        let additions = await fetchAppleCatalogSongs(
            queries: queries,
            seedSongs: existingSongs,
            maxCount: 24,
            idBase: 500_000 + page * 10_000
        )
        guard additions.isEmpty == false else { return [] }
        appendCachedDiscoveryExtras(additions)
        nextPlaybackPrefetchPage = max(nextPlaybackPrefetchPage, page + 1)
        return additions
    }

    func refreshSpotifySongsIfPossible(showMessage: Bool = false) async {
        guard spotifyAccessToken.isEmpty == false else { return }

        do {
            if spotifyTokenExpiresAt > 0,
               spotifyTokenExpiresAt - Date().timeIntervalSince1970 < 120,
               spotifyRefreshToken.isEmpty == false {
                let token = try await spotifyAuthenticator.refreshAccessToken(refreshToken: spotifyRefreshToken)
                spotifyAccessToken = token.accessToken
                spotifyRefreshToken = token.refreshToken ?? spotifyRefreshToken
                spotifyTokenExpiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn)).timeIntervalSince1970
            }

            spotifyPlaylists = try await SpotifyWebAPIClient.playlistOptions(accessToken: spotifyAccessToken, limit: 30)
            let drafts = try await SpotifyWebAPIClient.discoverySongDrafts(
                accessToken: spotifyAccessToken,
                maxCount: 60,
                playlistID: selectedSpotifyPlaylistID
            )
            spotifySongs = spotifySongs(from: drafts, artworkByID: [:])
            hydrateSpotifyArtwork(for: drafts)
            if aiRecommendationsEnabled {
                refreshRecommendations()
            }
            if showMessage {
                message = drafts.isEmpty ? "Spotify 已连接，但没有读到已收藏歌曲或歌单歌曲。" : "已导入 \(drafts.count) 首 Spotify 歌曲到首页"
            }
        } catch {
            if showMessage {
                message = "Spotify 已连接，但暂时没拉到歌单：\(error.localizedDescription)"
            }
        }
    }

    func selectSpotifyPlaylist(_ optionID: String) async {
        selectedSpotifyPlaylistID = optionID
        await refreshSpotifySongsIfPossible(showMessage: true)
    }

    private func spotifySongs(from drafts: [SpotifySongDraft], artworkByID: [String: UIImage]) -> [DemoSong] {
        let palettes = DemoSong.library.map(\.colors)
        return drafts.enumerated().map { index, draft in
            let palette = palettes[(index + draft.title.count) % palettes.count]
            let artworkImage = artworkByID[draft.id]
            let magicColor = artworkImage?.magicAverageColor ?? UIColor(songPalette: palette)
            return DemoSong(
                id: 700_000 + index,
                title: draft.title,
                artist: draft.artist,
                colors: palette,
                artworkImage: artworkImage,
                backdropImage: artworkImage?.playerBackdropImage,
                magicColor: Color(uiColor: magicColor),
                source: .spotify
            )
        }
    }

    private func hydrateSpotifyArtwork(for drafts: [SpotifySongDraft]) {
        Task { @MainActor in
            let imageDrafts = Array(drafts.prefix(24))
            var artworkByID: [String: UIImage] = [:]
            for draft in imageDrafts {
                guard let image = await ITunesSearchClient.artworkImage(from: draft.artworkURL) else { continue }
                artworkByID[draft.id] = image
                if artworkByID.count.isMultiple(of: 6) || artworkByID.count == imageDrafts.count {
                    spotifySongs = spotifySongs(from: drafts, artworkByID: artworkByID)
                }
            }
        }
    }

    private func mediaItemsFromLibrary() -> [MPMediaItem] {
        let queryItems: [MPMediaItem]
        if selectedApplePlaylistID == MusicPlaylistOption.allID {
            queryItems = MPMediaQuery.playlists().collections?.flatMap(\.items) ?? MPMediaQuery.songs().items ?? []
        } else {
            queryItems = appleMusicPlaylistCollections()
                .first(where: { playlistID(for: $0) == selectedApplePlaylistID })?
                .items ?? []
        }

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

    private func appleMusicPlaylists() -> [MusicPlaylistOption] {
        appleMusicPlaylistCollections().compactMap { collection in
            let id = playlistID(for: collection)
            guard id.isEmpty == false else { return nil }
            let name = (collection as? MPMediaPlaylist)?.name
                ?? collection.value(forProperty: MPMediaPlaylistPropertyName) as? String
                ?? "Apple Music 歌单"
            return MusicPlaylistOption(id: id, title: name, count: collection.items.count)
        }
    }

    private func appleMusicPlaylistCollections() -> [MPMediaItemCollection] {
        MPMediaQuery.playlists().collections ?? []
    }

    private func playlistID(for collection: MPMediaItemCollection) -> String {
        if let playlist = collection as? MPMediaPlaylist {
            return "\(playlist.persistentID)"
        }
        if let id = collection.value(forProperty: MPMediaPlaylistPropertyPersistentID) as? NSNumber {
            return id.stringValue
        }
        return ""
    }

    private func normalizedSongKey(title: String, artist: String) -> String {
        "\(normalizedTitleForRecommendation(title))|\(normalizedArtistForRecommendation(artist))"
    }

    private func normalizedTitleForRecommendation(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(
                of: #"[\(\[][^\)\]]*(remix|mixed|mix|edit|version|live|remaster|sped up|slowed|instrumental)[^\)\]]*[\)\]]"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedArtistForRecommendation(_ artist: String) -> String {
        artist
            .lowercased()
            .replacingOccurrences(of: #"(\s+feat\.?.*|\s+ft\.?.*)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lyricsCacheKey(for song: DemoSong) -> String {
        normalizedSongKey(title: song.title, artist: song.artist)
    }

    private static func extractLyrics(from item: MPMediaItem) -> String? {
        if let lyrics = item.value(forProperty: MPMediaItemPropertyLyrics) as? String {
            let trimmed = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func parseLyricsLines(from rawLyrics: String?) -> [String] {
        guard let rawLyrics else { return [] }
        return rawLyrics
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard line.isEmpty == false else { return false }
                guard line.hasPrefix("[") == false || line.hasSuffix("]") == false else { return false }
                return true
            }
    }

    private func fetchRemoteLyrics(for song: DemoSong) async -> String? {
        if let lyrics = try? await LRCLibClient.lyrics(title: song.title, artist: song.artist) {
            let trimmed = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }

        if let lyrics = try? await LyricsOVHClient.lyrics(title: song.title, artist: song.artist) {
            let trimmed = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }

        return nil
    }

    func play(_ song: DemoSong, in queueSongs: [DemoSong]? = nil) async {
        queuePlayback(for: song, in: queueSongs)
    }

    func queuePlayback(for song: DemoSong, in queueSongs: [DemoSong]? = nil) {
        guard song.isPlayable else {
            message = "这首是 AI 推荐，暂时没有可播放资源。"
            return
        }
        beginPlaybackLoading()
        queuedPlaybackTask?.cancel()
        playbackQueueWarmupTask?.cancel()
        playbackPrefetchTask?.cancel()
        playbackRequestID &+= 1
        let requestID = playbackRequestID
        let queueSnapshot = compactPlaybackQueueSnapshot(startingWith: song, in: queueSongs)
        if playingSongID != song.id {
            playingSongID = song.id
        }
        if currentSong?.id != song.id {
            currentSong = song
        }
        if isPlaying == false {
            isPlaying = true
        }

        queuedPlaybackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(88))
            guard !Task.isCancelled, requestID == playbackRequestID else { return }
            let player = MPMusicPlayerController.applicationMusicPlayer
            setPlaybackQueue(on: player, startingWith: song, in: queueSnapshot)
            prepareAndStartPlayback(on: player, song: song, queueSongs: queueSnapshot, requestID: requestID)
        }
    }

    func togglePlayback(for song: DemoSong, in queueSongs: [DemoSong]? = nil) async {
        guard song.isPlayable else {
            message = "这首是 AI 推荐，暂时没有可播放资源。"
            return
        }
        let player = MPMusicPlayerController.applicationMusicPlayer
        if player.playbackState == .playing, isPlayerCurrentlyOn(song, player: player) {
            player.pause()
            playingSongID = song.id
            currentSong = song
            isPlaying = false
            endPlaybackLoading()
            message = "已暂停：\(song.title)"
        } else if isPlayerCurrentlyOn(song, player: player) {
            player.play()
            playingSongID = song.id
            currentSong = song
            isPlaying = true
            endPlaybackLoading()
            message = "正在播放：\(song.title)"
        } else {
            queuePlayback(for: song, in: queueSongs)
        }
    }

    func startPlaybackSync() {
        guard playbackObservers.isEmpty else {
            syncPlaybackState()
            return
        }

        let player = MPMusicPlayerController.applicationMusicPlayer
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        playbackObservers = [
            center.addObserver(
                forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
                object: player,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncPlaybackState()
                }
            },
            center.addObserver(
                forName: .MPMusicPlayerControllerPlaybackStateDidChange,
                object: player,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncPlaybackState()
                }
            }
        ]
        syncPlaybackState()
    }

    func stopPlaybackSync() {
        guard playbackObservers.isEmpty == false else { return }
        playbackObservers.forEach(NotificationCenter.default.removeObserver)
        playbackObservers = []
        MPMusicPlayerController.applicationMusicPlayer.endGeneratingPlaybackNotifications()
    }

    func lyricLines(for song: DemoSong) -> [String] {
        let candidates = [
            song.lyricsText,
            currentSong?.id == song.id ? currentSong?.lyricsText : nil,
            fetchedLyricsByKey[lyricsCacheKey(for: song)],
            MPMusicPlayerController.applicationMusicPlayer.nowPlayingItem.flatMap(Self.extractLyrics(from:))
        ]

        for candidate in candidates {
            let parsed = Self.parseLyricsLines(from: candidate)
            if parsed.isEmpty == false {
                return parsed
            }
        }

        return []
    }

    func isLoadingLyrics(for song: DemoSong) -> Bool {
        loadingLyricKeys.contains(lyricsCacheKey(for: song))
    }

    func loadLyricsIfNeeded(for song: DemoSong) {
        let key = lyricsCacheKey(for: song)
        guard fetchedLyricsByKey[key] == nil else { return }
        guard loadingLyricKeys.contains(key) == false else { return }
        guard lyricLines(for: song).isEmpty else { return }

        loadingLyricKeys.insert(key)
        Task { @MainActor in
            defer { loadingLyricKeys.remove(key) }
            if let lyrics = await fetchRemoteLyrics(for: song) {
                fetchedLyricsByKey[key] = lyrics
            }
        }
    }

    private func syncPlaybackState() {
        let player = MPMusicPlayerController.applicationMusicPlayer
        isPlaying = player.playbackState == .playing
        guard let item = player.nowPlayingItem else {
            return
        }

        if let matchedSong = song(matching: item) {
            currentSong = matchedSong
            playingSongID = matchedSong.id
        } else {
            let fallback = song(from: item)
            currentSong = fallback
            playingSongID = fallback.id
        }
    }

    private func song(matching item: MPMediaItem) -> DemoSong? {
        let allSongs = librarySongs + recommendedSongs + discoveryExtraSongs
        if let match = allSongs.first(where: { song in
            song.mediaItem?.persistentID == item.persistentID
        }) {
            return enrichedSong(match, with: item)
        }
        guard let storeID = item.safePlaybackStoreID else { return nil }
        guard let match = allSongs.first(where: { $0.storeID == storeID }) else { return nil }
        return enrichedSong(match, with: item)
    }

    private func song(from item: MPMediaItem) -> DemoSong {
        let artworkImage = item.artwork?.image(at: CGSize(width: 220, height: 220))
        let paletteIndex = (item.title?.count ?? 0) % DemoSong.library.count
        let palette = DemoSong.library[paletteIndex].colors
        let magicColor = artworkImage?.magicAverageColor ?? UIColor(songPalette: palette)
        return DemoSong(
            id: 900_000 + abs(item.title?.hashValue ?? Int(item.persistentID) % 80_000),
            title: item.title ?? "Untitled",
            artist: item.artist ?? "Unknown Artist",
            colors: palette,
            mediaItem: item,
            storeID: item.safePlaybackStoreID,
            artworkImage: artworkImage,
            backdropImage: artworkImage?.playerBackdropImage,
            lyricsText: Self.extractLyrics(from: item),
            magicColor: Color(uiColor: magicColor),
            source: .library
        )
    }

    private func enrichedSong(_ song: DemoSong, with item: MPMediaItem) -> DemoSong {
        let artworkImage = song.artworkImage ?? item.artwork?.image(at: CGSize(width: 220, height: 220))
        let magicColor = song.artworkImage == nil
            ? (artworkImage?.magicAverageColor.map(Color.init(uiColor:)) ?? song.magicColor)
            : song.magicColor
        return DemoSong(
            id: song.id,
            title: item.title ?? song.title,
            artist: item.artist ?? song.artist,
            colors: song.colors,
            mediaItem: song.mediaItem ?? item,
            storeID: song.storeID ?? item.safePlaybackStoreID,
            artworkImage: artworkImage,
            backdropImage: artworkImage?.playerBackdropImage ?? song.backdropImage,
            lyricsText: Self.extractLyrics(from: item) ?? song.lyricsText,
            magicColor: magicColor,
            source: song.source
        )
    }

    private func setPlaybackQueue(on player: MPMusicPlayerController, startingWith song: DemoSong, in queueSongs: [DemoSong]?) {
        prepareImmediatePlaybackQueue(on: player, startingWith: song)
    }

    private func prepareAndStartPlayback(
        on player: MPMusicPlayerController,
        song: DemoSong,
        queueSongs: [DemoSong]?,
        requestID: Int
    ) {
        player.prepareToPlay { [weak self] error in
            Task { @MainActor in
                guard let self, self.playingSongID == song.id, self.playbackRequestID == requestID else { return }
                if let error {
                    self.endPlaybackLoading()
                    self.message = "加载这首歌有点慢：\(error.localizedDescription)"
                    return
                }
                player.play()
                self.scheduleContinuousQueueWarmup(startingWith: song, in: queueSongs, requestID: requestID)
                self.schedulePlaybackPrefetch(startingWith: song, in: queueSongs, requestID: requestID)
                self.endPlaybackLoading()
                self.message = "正在播放：\(song.title)"
            }
        }
    }

    private func prepareImmediatePlaybackQueue(on player: MPMusicPlayerController, startingWith song: DemoSong) {
        if let mediaItem = song.mediaItem {
            player.setQueue(with: MPMediaItemCollection(items: [mediaItem]))
            player.nowPlayingItem = mediaItem
        } else if let storeID = song.storeID {
            player.setQueue(with: [storeID])
        }
    }

    private func scheduleContinuousQueueWarmup(startingWith song: DemoSong, in queueSongs: [DemoSong]?, requestID: Int) {
        playbackQueueWarmupTask?.cancel()

        playbackQueueWarmupTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, playbackRequestID == requestID, playingSongID == song.id, isPlaying else { return }
            let player = MPMusicPlayerController.applicationMusicPlayer
            prepareContinuousQueue(on: player, startingWith: song, in: queueSongs)
        }
    }

    private func schedulePlaybackPrefetch(startingWith song: DemoSong, in queueSongs: [DemoSong]?, requestID: Int) {
        playbackPrefetchTask?.cancel()
        playbackPrefetchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(780))
            guard !Task.isCancelled, playbackRequestID == requestID, playingSongID == song.id else { return }

            let upcomingSongs = playbackQueueSongs(startingWith: song, in: queueSongs)
            PlayerArtworkWarmupCache.shared.preload(songs: Array(upcomingSongs.dropFirst().prefix(playbackPrefetchLimit)))

            guard aiRecommendationsEnabled, discoveryExtraSongs.count < discoveryExtraSongLimit else { return }
            let page = nextPlaybackPrefetchPage
            guard loadedPlaybackPrefetchPages.insert(page).inserted else { return }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, playbackRequestID == requestID, playingSongID == song.id else { return }
            _ = await loadMoreDiscoverySongs(page: page)
        }
    }

    private func compactPlaybackQueueSnapshot(startingWith song: DemoSong, in queueSongs: [DemoSong]?) -> [DemoSong] {
        var snapshot = playbackQueueSongs(startingWith: song, in: queueSongs)
        if snapshot.first?.id != song.id {
            snapshot.removeAll { $0.id == song.id }
            snapshot.insert(song, at: 0)
        }
        return Array(snapshot.prefix(playbackQueueLimit))
    }

    private func prepareContinuousQueue(
        on player: MPMusicPlayerController,
        startingWith song: DemoSong,
        in queueSongs: [DemoSong]?
    ) {
        let rotatedSongs = playbackQueueSongs(startingWith: song, in: queueSongs)
        guard rotatedSongs.isEmpty == false else { return }
        let items = rotatedSongs.compactMap(\.mediaItem)
        if let mediaItem = song.mediaItem {
            player.setQueue(with: MPMediaItemCollection(items: items.isEmpty ? [mediaItem] : items))
            player.nowPlayingItem = mediaItem
            return
        }

        let storeIDs = rotatedSongs.compactMap(\.storeID)
        if storeIDs.isEmpty == false, song.storeID != nil {
            player.setQueue(with: storeIDs)
        }
    }

    private func playbackQueueSongs(startingWith song: DemoSong, in queueSongs: [DemoSong]?) -> [DemoSong] {
        let source: [DemoSong]
        if let queueSongs, queueSongs.isEmpty == false {
            source = queueSongs
        } else {
            source = discoverySongs.isEmpty ? librarySongs : discoverySongs
        }

        let uniqueSongs = uniquePlayableSongs(from: source)
        guard let selectedIndex = uniqueSongs.firstIndex(where: { $0.id == song.id }) else {
            return Array(uniqueSongs.prefix(playbackQueueLimit))
        }

        let rotatedSongs = Array(uniqueSongs[selectedIndex...]) + Array(uniqueSongs[..<selectedIndex])
        return Array(rotatedSongs.prefix(playbackQueueLimit))
    }

    private func uniquePlayableSongs(from songs: [DemoSong]) -> [DemoSong] {
        var seenIDs = Set<MPMediaEntityPersistentID>()
        var seenStoreIDs = Set<String>()
        var seenSongKeys = Set<String>()
        return songs.compactMap { song in
            let key = normalizedSongKey(title: song.title, artist: song.artist)
            guard seenSongKeys.insert(key).inserted else { return nil }
            if let storeID = song.storeID {
                guard seenStoreIDs.insert(storeID).inserted else { return nil }
                return song
            }
            guard let mediaItem = song.mediaItem else { return nil }
            guard seenIDs.insert(mediaItem.persistentID).inserted else { return nil }
            return song
        }
    }

    private func appendCachedDiscoveryExtras(_ additions: [DemoSong]) {
        guard additions.isEmpty == false else { return }
        let mergedSongs = uniqueDiscoverySongs(from: discoveryExtraSongs + additions)
        if mergedSongs.count > discoveryExtraSongLimit {
            discoveryExtraSongs = Array(mergedSongs.suffix(discoveryExtraSongLimit))
        } else {
            discoveryExtraSongs = mergedSongs
        }
    }

    private func isPlayerCurrentlyOn(_ song: DemoSong, player: MPMusicPlayerController) -> Bool {
        if let mediaItem = song.mediaItem, player.nowPlayingItem?.persistentID == mediaItem.persistentID {
            return true
        }
        if let storeID = song.storeID, player.nowPlayingItem?.safePlaybackStoreID == storeID {
            return true
        }
        return false
    }

    private func uniqueDiscoverySongs(from songs: [DemoSong]) -> [DemoSong] {
        var seenKeys = Set<String>()
        var seenStoreIDs = Set<String>()
        var seenMediaIDs = Set<MPMediaEntityPersistentID>()
        return songs.compactMap { song in
            guard song.isPlaceholder == false else { return song }
            let key = normalizedSongKey(title: song.title, artist: song.artist)
            guard seenKeys.insert(key).inserted else { return nil }
            if let storeID = song.storeID {
                guard seenStoreIDs.insert(storeID).inserted else { return nil }
            }
            if let mediaItem = song.mediaItem {
                guard seenMediaIDs.insert(mediaItem.persistentID).inserted else { return nil }
            }
            return song
        }
    }

    private func refreshRecommendations() {
        guard aiRecommendationsEnabled else {
            recommendationTask?.cancel()
            recommendedSongs = []
            discoveryExtraSongs = []
            nextPlaybackPrefetchPage = 1
            loadedPlaybackPrefetchPages.removeAll()
            return
        }
        recommendationTask?.cancel()
        recommendedSongs = []
        discoveryExtraSongs = []
        nextPlaybackPrefetchPage = 1
        loadedPlaybackPrefetchPages.removeAll()

        let seedSongs = Array((spotifySongs + (librarySongs.isEmpty ? DemoSong.library : librarySongs)).prefix(24))
        recommendationTask = Task { @MainActor in
            let recommendations = await fetchAppleCatalogRecommendations(from: seedSongs)
            guard !Task.isCancelled else { return }
            recommendedSongs = recommendations
        }
    }

    private func fetchAppleCatalogRecommendations(from seedSongs: [DemoSong]) async -> [DemoSong] {
        let chartSongs = await fetchAppleChartSongs(seedSongs: seedSongs, maxCount: 18)
        let latestSongs = await fetchAppleCatalogSongs(
            queries: latestReleaseQueries(from: seedSongs),
            seedSongs: seedSongs + chartSongs,
            maxCount: 24,
            idBase: 200_000
        )
        let searchSongs = await fetchAppleCatalogSongs(
            queries: recommendationQueries(from: seedSongs),
            seedSongs: seedSongs + chartSongs + latestSongs,
            maxCount: 36,
            idBase: 220_000
        )
        return Array(uniqueDiscoverySongs(from: latestSongs + chartSongs + searchSongs).prefix(60))
    }

    private func fetchAppleChartSongs(seedSongs: [DemoSong], maxCount: Int) async -> [DemoSong] {
        do {
            let tracks = try await AppleMusicRSSClient.topSongs(limit: 50)
            return await songs(
                from: tracks,
                seedSongs: seedSongs,
                maxCount: maxCount,
                idBase: 180_000
            )
        } catch {
            return []
        }
    }

    private func fetchAppleCatalogSongs(
        queries: [String],
        seedSongs: [DemoSong],
        maxCount: Int,
        idBase: Int
    ) async -> [DemoSong] {
        var results: [DemoSong] = []
        var seenKeys = Set(seedSongs.map { normalizedSongKey(title: $0.title, artist: $0.artist) })
        var seenStoreIDs = Set(seedSongs.compactMap(\.storeID))

        for query in queries {
            guard results.count < maxCount else { break }
            do {
                let tracks = try await ITunesSearchClient.search(term: query, limit: 18)
                let songs = await songs(
                    from: tracks.prioritizingRecentReleases,
                    seedSongs: seedSongs + results,
                    maxCount: maxCount - results.count,
                    idBase: idBase + results.count
                )
                for song in songs {
                    guard seenKeys.insert(normalizedSongKey(title: song.title, artist: song.artist)).inserted else { continue }
                    guard seenStoreIDs.insert(song.storeID ?? "\(song.id)").inserted else { continue }
                    results.append(song)
                }
            } catch {
                continue
            }
        }

        return results
    }

    private func songs(
        from tracks: [ITunesTrack],
        seedSongs: [DemoSong],
        maxCount: Int,
        idBase: Int
    ) async -> [DemoSong] {
        var results: [DemoSong] = []
        var seenKeys = Set(seedSongs.map { normalizedSongKey(title: $0.title, artist: $0.artist) })
        var seenStoreIDs = Set(seedSongs.compactMap(\.storeID))
        let palettes = DemoSong.library.map(\.colors)

        for track in tracks {
            guard results.count < maxCount else { break }
            let songKey = normalizedSongKey(title: track.trackName, artist: track.artistName)
            guard seenKeys.insert(songKey).inserted else { continue }
            guard seenStoreIDs.insert(track.trackID).inserted else { continue }

            let artworkImage = await ITunesSearchClient.artworkImage(from: track.artworkURL100)
            let palette = palettes[(results.count + track.trackName.count) % palettes.count]
            let magicColor = artworkImage?.magicAverageColor ?? UIColor(songPalette: palette)
            results.append(
                DemoSong(
                    id: idBase + results.count,
                    title: track.trackName,
                    artist: track.artistName,
                    colors: palette,
                    storeID: track.trackID,
                    artworkImage: artworkImage,
                    backdropImage: artworkImage?.playerBackdropImage,
                    magicColor: Color(uiColor: magicColor),
                    source: .recommendation
                )
            )
        }

        return results
    }

    private func moreDiscoveryQueries(page: Int) -> [String] {
        let timeBased: [String]
        switch HomeTimeMood.current {
        case .morning:
            timeBased = [
                "morning acoustic pop",
                "sunny morning songs",
                "coffeehouse pop",
                "fresh start playlist",
                "bright indie pop",
                "morning commute music"
            ]
        case .afternoon:
            timeBased = [
                "afternoon pop hits",
                "workday energy songs",
                "dance pop radio",
                "feel good pop",
                "today hits",
                "new music daily"
            ]
        case .evening:
            timeBased = [
                "evening chill songs",
                "night drive songs",
                "cinematic pop",
                "indie evening playlist",
                "r&b favorites",
                "soft rock essentials"
            ]
        case .lateNight:
            timeBased = [
                "late night songs",
                "dream pop playlist",
                "ambient pop",
                "after dark r&b",
                "sleepy indie",
                "midnight drive music"
            ]
        }
        let editorial = [
            "Apple Music Today's Hits",
            "Apple Music Pop",
            "Apple Music New Music Daily",
            "Apple Music New Releases",
            "Apple Music Hits",
            "Apple Music Pop Hits",
            "Apple Music A-List Pop",
            "Apple Music new songs",
            "Apple Music latest releases",
            "popular music playlist",
            "new music playlist",
            "new pop releases",
            "new music daily",
            "today hits",
            "global pop hits",
            "indie pop new",
            "fresh finds music",
            "daily top songs",
            "hot tracks"
        ]
        let mood = [
            "night drive songs",
            "morning pop songs",
            "chill electronic",
            "alternative discoveries",
            "dance pop radio",
            "cinematic pop",
            "soft rock essentials",
            "r&b favorites"
        ]
        let style = inferredStyleTerms(from: librarySongs).map { "\($0) recommendations" }
        let pool = (page % 2 == 0 ? timeBased + style + editorial + mood : timeBased + mood + style + editorial)
        let start = (page * 4) % max(pool.count, 1)
        return (0..<8).map { pool[(start + $0) % pool.count] }
    }

    private func latestReleaseQueries(from songs: [DemoSong]) -> [String] {
        let recentArtistQueries = topArtists(from: songs, limit: 6).flatMap { artist in
            [
                "\(artist) latest song",
                "\(artist) new single",
                "\(artist) new release"
            ]
        }
        let editorialQueries = [
            "new music Friday pop",
            "latest pop releases",
            "new songs this week",
            "today new music",
            "new release pop",
            "fresh pop singles",
            "Madonna Confessions II",
            "Madonna new song",
            "Charli xcx latest song",
            "Charli xcx Wink Wink",
            "Charli xcx SS26"
        ]
        return Array((recentArtistQueries + editorialQueries).prefix(28))
    }

    private func recommendationQueries(from songs: [DemoSong]) -> [String] {
        let artists = topArtists(from: songs, limit: 8)
        let styleTerms = inferredStyleTerms(from: songs)
        let artistQueries = artists.flatMap { artist in
            [
                "\(artist) latest songs",
                "\(artist) top songs"
            ]
        }
        return Array((artistQueries + styleTerms).prefix(14))
    }

    private func topArtists(from songs: [DemoSong], limit: Int) -> [String] {
        Array(
            Dictionary(grouping: songs, by: \.artist)
                .sorted { $0.value.count > $1.value.count }
                .map(\.key)
                .filter { $0 != "Unknown Artist" && $0.isEmpty == false }
                .prefix(limit)
        )
    }

    private func inferredStyleTerms(from songs: [DemoSong]) -> [String] {
        let text = songs.map { "\($0.title) \($0.artist)" }.joined(separator: " ").lowercased()
        var terms: [String] = []
        if text.contains("taylor") || text.contains("sabrina") || text.contains("dua") {
            terms.append(contentsOf: ["fresh pop hits", "dance pop essentials"])
        }
        if text.contains("u2") || text.contains("rolling") || text.contains("rock") {
            terms.append(contentsOf: ["alternative rock essentials", "modern rock songs"])
        }
        if text.contains("justin") || text.contains("weeknd") || text.contains("r&b") {
            terms.append(contentsOf: ["smooth r&b pop", "night drive pop"])
        }
        if text.contains("joe hisaishi") || text.contains("soundtrack") || text.contains("classical") {
            terms.append(contentsOf: ["cinematic soundtrack", "modern classical calm"])
        }
        if terms.isEmpty {
            terms = ["indie pop essentials", "new music discovery", "chill pop songs", "alternative favorites"]
        }
        return terms
    }

    private func interleavedDiscoverySongs(librarySongs: [DemoSong], recommendedSongs: [DemoSong]) -> [DemoSong] {
        guard recommendedSongs.isEmpty == false else { return librarySongs }
        var mixed: [DemoSong] = []
        let maxCount = max(librarySongs.count, recommendedSongs.count)
        for index in 0..<maxCount {
            if librarySongs.indices.contains(index) {
                mixed.append(librarySongs[index])
            }
            if index % 2 == 0, recommendedSongs.indices.contains(index / 2) {
                mixed.append(recommendedSongs[index / 2])
            }
        }
        return mixed
    }

    private func beginPlaybackLoading() {
        playbackLoadingTask?.cancel()
        playbackLoadingTask = nil
        isPlaybackTransitioning = true
        showPlaybackLoadingToast = false
    }

    private func endPlaybackLoading() {
        playbackLoadingTask?.cancel()
        playbackLoadingTask = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            showPlaybackLoadingToast = false
            try? await Task.sleep(for: .milliseconds(120))
            isPlaybackTransitioning = false
        }
    }

    func connectSpotify() async {
        guard !isConnectingSpotify else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIPasteboard.general.string = SpotifyAuthConfig.redirectURI
        message = "已复制 Spotify 回调地址：\(SpotifyAuthConfig.redirectURI)"
        isConnectingSpotify = true
        defer { isConnectingSpotify = false }

        do {
            try? await Task.sleep(for: .milliseconds(650))
            let token = try await spotifyAuthenticator.authorize()
            spotifyAccessToken = token.accessToken
            spotifyRefreshToken = token.refreshToken ?? spotifyRefreshToken
            spotifyTokenExpiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn)).timeIntervalSince1970
            await refreshSpotifySongsIfPossible(showMessage: true)
        } catch {
            message = """
            \(error.localizedDescription)
            Client ID: \(SpotifyAuthConfig.clientID)
            Redirect: \(SpotifyAuthConfig.redirectURI)
            """
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
    static let clientID = "bfa6de6c24d148db906470a5a4bf0345"
    static let redirectPort: UInt16 = 8888
    static let redirectPath = "/callback"
    static let redirectURI = "http://127.0.0.1:8888/callback"
    static let scopes = [
        "user-read-email",
        "user-read-private",
        "user-library-read",
        "playlist-read-private"
    ]
}

private enum SpotifyWebAPIClient {
    static func playlistOptions(accessToken: String, limit: Int) async throws -> [MusicPlaylistOption] {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/playlists")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components?.url else { return [] }

        let response = try await get(SpotifyPlaylistsResponse.self, url: url, accessToken: accessToken)
        return response.items.map { playlist in
            MusicPlaylistOption(id: playlist.id, title: playlist.name, count: playlist.tracks?.total ?? 0)
        }
    }

    static func discoverySongDrafts(
        accessToken: String,
        maxCount: Int,
        playlistID: String
    ) async throws -> [SpotifySongDraft] {
        if playlistID != MusicPlaylistOption.allID {
            return songDrafts(
                from: try await playlistTracks(accessToken: accessToken, playlistID: playlistID, limit: maxCount),
                maxCount: maxCount
            )
        }

        async let savedTracks = savedTracks(accessToken: accessToken, limit: 24)
        async let playlistTracks = tracksFromCurrentUserPlaylists(accessToken: accessToken, playlistLimit: 10, trackLimit: 12)
        let tracks = try await savedTracks + playlistTracks
        return songDrafts(from: tracks, maxCount: maxCount)
    }

    private static func savedTracks(accessToken: String, limit: Int) async throws -> [SpotifyTrack] {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/tracks")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components?.url else { return [] }

        let response = try await get(SpotifySavedTracksResponse.self, url: url, accessToken: accessToken)
        return response.items.compactMap(\.track)
    }

    private static func tracksFromCurrentUserPlaylists(
        accessToken: String,
        playlistLimit: Int,
        trackLimit: Int
    ) async throws -> [SpotifyTrack] {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/playlists")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "\(playlistLimit)")
        ]
        guard let url = components?.url else { return [] }

        let response = try await get(SpotifyPlaylistsResponse.self, url: url, accessToken: accessToken)
        var tracks: [SpotifyTrack] = []
        for playlist in response.items.prefix(playlistLimit) {
            guard tracks.count < playlistLimit * trackLimit else { break }
            tracks.append(contentsOf: try await playlistTracks(accessToken: accessToken, playlistID: playlist.id, limit: trackLimit))
        }
        return tracks
    }

    private static func playlistTracks(accessToken: String, playlistID: String, limit: Int) async throws -> [SpotifyTrack] {
        var components = URLComponents(string: "https://api.spotify.com/v1/playlists/\(playlistID)/tracks")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components?.url else { return [] }

        let response = try await get(SpotifyPlaylistTracksResponse.self, url: url, accessToken: accessToken)
        return response.items.compactMap(\.track)
    }

    private static func get<T: Decodable>(_ type: T.Type, url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw SpotifyAuthError.invalidTokenResponse
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func songDrafts(from tracks: [SpotifyTrack], maxCount: Int) -> [SpotifySongDraft] {
        var drafts: [SpotifySongDraft] = []
        var seenKeys = Set<String>()

        for track in tracks {
            guard drafts.count < maxCount else { break }
            let artist = track.artists.map(\.name).joined(separator: ", ")
            let key = "\(track.name.lowercased())|\(artist.lowercased())"
            guard seenKeys.insert(key).inserted else { continue }
            drafts.append(
                SpotifySongDraft(
                    id: track.id,
                    title: track.name,
                    artist: artist.isEmpty ? "Spotify" : artist,
                    artworkURL: track.album?.images.first?.url
                )
            )
        }

        return drafts
    }
}

private struct SpotifySongDraft: Identifiable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: String?
}

private struct SpotifySavedTracksResponse: Decodable {
    let items: [SpotifySavedTrackItem]
}

private struct SpotifySavedTrackItem: Decodable {
    let track: SpotifyTrack?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        track = try? container.decode(SpotifyTrack.self, forKey: .track)
    }

    private enum CodingKeys: String, CodingKey {
        case track
    }
}

private struct SpotifyPlaylistsResponse: Decodable {
    let items: [SpotifyPlaylistSummary]
}

private struct SpotifyPlaylistSummary: Decodable {
    let id: String
    let name: String
    let tracks: SpotifyPlaylistTracksSummary?
}

private struct SpotifyPlaylistTracksSummary: Decodable {
    let total: Int
}

private struct SpotifyPlaylistTracksResponse: Decodable {
    let items: [SpotifyPlaylistTrackItem]
}

private struct SpotifyPlaylistTrackItem: Decodable {
    let track: SpotifyTrack?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        track = try? container.decode(SpotifyTrack.self, forKey: .track)
    }

    private enum CodingKeys: String, CodingKey {
        case track
    }
}

private struct SpotifyTrack: Decodable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum?
}

private struct SpotifyArtist: Decodable {
    let name: String
}

private struct SpotifyAlbum: Decodable {
    let images: [SpotifyImage]
}

private struct SpotifyImage: Decodable {
    let url: String
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
        let redirectServer = try SpotifyLocalRedirectServer(
            port: SpotifyAuthConfig.redirectPort,
            path: SpotifyAuthConfig.redirectPath
        )
        defer { redirectServer.stop() }
        let redirectURI = SpotifyAuthConfig.redirectURI

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: SpotifyAuthConfig.clientID),
            URLQueryItem(name: "scope", value: SpotifyAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]

        guard let authURL = components?.url else {
            throw SpotifyAuthError.invalidAuthorizeURL
        }
        UIPasteboard.general.string = authURL.absoluteString

        let callbackURL = try await authenticate(with: authURL, redirectServer: redirectServer)
        guard
            let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value == state,
            let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw SpotifyAuthError.missingCallbackCode
        }

        return try await exchangeToken(code: code, verifier: verifier, redirectURI: redirectURI)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func authenticate(with url: URL, redirectServer: SpotifyLocalRedirectServer) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let resume: (Result<URL, Error>) -> Void = { result in
                guard didResume == false else { return }
                didResume = true
                self.session?.cancel()
                switch result {
                case .success(let callbackURL):
                    continuation.resume(returning: callbackURL)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            redirectServer.onCallback = { callbackURL in
                resume(.success(callbackURL))
            }

            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { _, error in
                if let error {
                    resume(.failure(error))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    private func exchangeToken(code: String, verifier: String, redirectURI: String) async throws -> SpotifyTokenResponse {
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
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw SpotifyAuthError.invalidTokenResponse
        }

        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }

    func refreshAccessToken(refreshToken: String) async throws -> SpotifyTokenResponse {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
            throw SpotifyAuthError.invalidTokenResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyAuthConfig.clientID),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
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

private final class SpotifyLocalRedirectServer {
    var onCallback: ((URL) -> Void)?

    private let listener: NWListener
    private let path: String

    init(port: UInt16, path: String) throws {
        self.path = path
        guard let fixedPort = NWEndpoint.Port(rawValue: port) else {
            throw SpotifyAuthError.invalidAuthorizeURL
        }
        listener = try NWListener(using: .tcp, on: fixedPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: .main)
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self,
                  let data,
                  let request = String(data: data, encoding: .utf8),
                  let requestLine = request.components(separatedBy: "\r\n").first else {
                connection.cancel()
                return
            }

            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else {
                connection.cancel()
                return
            }

            let target = String(parts[1])
            let body = "Spotify connected. You can return to musicfind."
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/plain; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """

            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            guard target.hasPrefix(self.path),
                  let callbackURL = URL(string: "http://127.0.0.1\(target)") else { return }
            onCallback?(callbackURL)
        }
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
    let songs: [DemoSong]
    @StateObject private var motion = MotionGravityObserver()
    @State private var badges: [PhysicsBadge] = []
    @State private var lastSize: CGSize = .zero
    @State private var lastSongIDs: [Int] = []
    @State private var lastCollisionHapticAt: Date = .distantPast

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
            .onChange(of: panelSongs.map(\.id)) { _ in
                resetBadges(in: proxy.size, force: true)
            }
            .onReceive(frameRate) { _ in
                stepBadges(in: proxy.size)
            }
        }
    }

    private var panelSongs: [DemoSong] {
        let source = songs.isEmpty ? DemoSong.library : songs
        return Array(source.prefix(16))
    }

    private func resetBadges(in size: CGSize, force: Bool = false) {
        let ids = panelSongs.map(\.id)
        guard size.width > 10, size.height > 10, force || size != lastSize || ids != lastSongIDs else { return }
        lastSize = size
        lastSongIDs = ids
        let columns: [CGFloat] = [0.13, 0.31, 0.49, 0.67, 0.85]
        badges = panelSongs.enumerated().map { index, song in
            let radius: CGFloat = [26, 30, 24, 28, 32, 25, 29, 27][index % 8]
            let column = columns[index % columns.count]
            let row = CGFloat(index / columns.count)
            return PhysicsBadge(
                id: song.id,
                radius: radius,
                song: song,
                position: CGPoint(x: size.width * column, y: 44 + row * 50),
                velocity: CGPoint(x: CGFloat(index % 2 == 0 ? 40 : -34), y: CGFloat(index % 3 == 0 ? 20 : -24))
            )
        }
    }

    private func stepBadges(in size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }

        var next = badges
        var strongestImpact: CGFloat = 0
        let gravity = motion.gravity
        let acceleration = CGPoint(x: CGFloat(gravity.x) * 1_020, y: CGFloat(-gravity.y) * 1_020)
        let dt: CGFloat = 1.0 / 60.0
        let damping: CGFloat = 0.992

        for index in next.indices {
            next[index].velocity.x = (next[index].velocity.x + acceleration.x * dt) * damping
            next[index].velocity.y = (next[index].velocity.y + acceleration.y * dt) * damping
            next[index].position.x += next[index].velocity.x * dt
            next[index].position.y += next[index].velocity.y * dt

            let radius = next[index].radius
            if next[index].position.x < radius {
                strongestImpact = max(strongestImpact, abs(next[index].velocity.x))
                next[index].position.x = radius
                next[index].velocity.x = abs(next[index].velocity.x) * 0.80
            } else if next[index].position.x > size.width - radius {
                strongestImpact = max(strongestImpact, abs(next[index].velocity.x))
                next[index].position.x = size.width - radius
                next[index].velocity.x = -abs(next[index].velocity.x) * 0.80
            }

            if next[index].position.y < radius {
                strongestImpact = max(strongestImpact, abs(next[index].velocity.y))
                next[index].position.y = radius
                next[index].velocity.y = abs(next[index].velocity.y) * 0.80
            } else if next[index].position.y > size.height - radius {
                strongestImpact = max(strongestImpact, abs(next[index].velocity.y))
                next[index].position.y = size.height - radius
                next[index].velocity.y = -abs(next[index].velocity.y) * 0.80
            }
        }

        for left in next.indices {
            for right in next.indices where right > left {
                strongestImpact = max(strongestImpact, resolveCollision(left, right, badges: &next))
            }
        }

        badges = next
        triggerCollisionHapticIfNeeded(strength: strongestImpact)
    }

    private func resolveCollision(_ left: Int, _ right: Int, badges: inout [PhysicsBadge]) -> CGFloat {
        let delta = CGPoint(
            x: badges[right].position.x - badges[left].position.x,
            y: badges[right].position.y - badges[left].position.y
        )
        let distance = max(0.001, sqrt(delta.x * delta.x + delta.y * delta.y))
        let minimumDistance = badges[left].radius + badges[right].radius
        guard distance < minimumDistance else { return 0 }

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
        guard speed < 0 else { return 0 }

        let impulse = -speed * 0.82
        badges[left].velocity.x -= normal.x * impulse
        badges[left].velocity.y -= normal.y * impulse
        badges[right].velocity.x += normal.x * impulse
        badges[right].velocity.y += normal.y * impulse
        return impulse
    }

    private func triggerCollisionHapticIfNeeded(strength: CGFloat) {
        guard strength > 38 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCollisionHapticAt) > 0.07 else { return }
        lastCollisionHapticAt = now
        let intensity = min(0.95, max(0.40, strength / 420))
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: intensity)
    }
}

private struct BadgeCircle: View {
    let badge: PhysicsBadge

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: badge.song.colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let artworkImage = PlayerArtworkWarmupCache.shared.artwork(for: badge.song) ?? badge.song.artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: badge.radius * 2, height: badge.radius * 2)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: badge.song.magicColor.opacity(0.22), radius: 12, y: 7)
    }
}

private struct PhysicsBadge: Identifiable {
    let id: Int
    let radius: CGFloat
    let song: DemoSong
    var position: CGPoint = .zero
    var velocity: CGPoint = .zero
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
    @Published var shakeEventID = UUID()

    private let manager = CMMotionManager()
    private var lastShakeDate = Date.distantPast
    private var shakeStrikeCount = 0
    private var lastStrikeDate = Date.distantPast
    private var lastMagnitude = 1.0
    private var lastAcceleration: CMAcceleration?

    func start() {
        guard manager.isAccelerometerAvailable else { return }
        shakeStrikeCount = 0
        lastStrikeDate = .distantPast
        lastMagnitude = 1.0
        lastAcceleration = nil
        manager.accelerometerUpdateInterval = 1.0 / 45.0
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
        let directionalImpulse: Double
        if let previous = lastAcceleration {
            let dx = acceleration.x - previous.x
            let dy = acceleration.y - previous.y
            let dz = acceleration.z - previous.z
            directionalImpulse = sqrt(dx * dx + dy * dy + dz * dz)
        } else {
            directionalImpulse = 0
        }
        let horizontalImpulse = max(abs(acceleration.x), abs(acceleration.y))
        lastAcceleration = acceleration
        lastMagnitude = magnitude

        let now = Date()
        guard now.timeIntervalSince(lastShakeDate) > 0.86 else { return }

        let isShakeStrike = magnitude > 2.05 ||
            impulse > 0.82 ||
            directionalImpulse > 1.05 ||
            horizontalImpulse > 1.70

        guard isShakeStrike else {
            if now.timeIntervalSince(lastStrikeDate) > 0.42 {
                shakeStrikeCount = 0
            }
            return
        }

        if now.timeIntervalSince(lastStrikeDate) > 0.46 {
            shakeStrikeCount = 1
        } else {
            shakeStrikeCount += 1
        }
        lastStrikeDate = now

        guard shakeStrikeCount >= 2 else { return }
        shakeStrikeCount = 0
        lastShakeDate = now
        shakeCount += 1
        shakeEventID = UUID()
    }
}

private struct LyricsOverlayView: View {
    let song: DemoSong
    let lyricLines: [String]
    let isLyricsLoading: Bool
    let isPlaying: Bool
    let isContentVisible: Bool
    let onClose: () -> Void
    let onTogglePlayback: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let modalTopInset = safeTop + 60
            let modalBottomInset = max(proxy.safeAreaInsets.bottom + 10, 18)

            VStack {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(.white.opacity(0.34))
                        .frame(width: 54, height: 5)
                        .padding(.top, 12)
                        .padding(.bottom, 26)
                        .onTapGesture(perform: onClose)

                    HStack(alignment: .center, spacing: 18) {
                        overlayArtwork

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.system(size: 34, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)

                            Text(song.artist)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            if isLyricsLoading {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("正在搜索这首歌的歌词")
                                        .font(.system(size: 32, weight: .heavy))
                                        .foregroundStyle(.white.opacity(0.94))

                                    Text("先从 Apple Music 读，拿不到就自动去外部歌词源补。")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.54))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, 12)
                            } else if lyricLines.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("暂时没有读到这首歌的歌词")
                                        .font(.system(size: 32, weight: .heavy))
                                        .foregroundStyle(.white.opacity(0.94))

                                    Text("Apple Music 和外部歌词源这次都没有匹配到，换一首歌或等我继续补更多来源。")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.54))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, 12)
                            } else {
                                ForEach(Array(lyricLines.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(size: index == 0 ? 34 : 29, weight: .heavy))
                                        .foregroundStyle(.white.opacity(0.88))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 66)
                        .padding(.bottom, 140)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.22),
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.10)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        if let backdropImage = song.backdropImage ?? song.artworkImage {
                            Image(uiImage: backdropImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .overlay(Color.black.opacity(0.72))
                                .blur(radius: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        }

                        LinearGradient(
                            colors: [
                                .white.opacity(0.14),
                                .black.opacity(0.08),
                                song.magicColor.opacity(0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
                .padding(.top, modalTopInset)
                .padding(.horizontal, 10)
                .padding(.bottom, modalBottomInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offset(y: dragOffset)
            .opacity(isContentVisible ? 1 : 0)
            .scaleEffect(isContentVisible ? 1 : 0.98, anchor: .top)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard value.translation.height > 0 else { return }
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let shouldClose = value.translation.height > 110 || value.predictedEndTranslation.height > 180
                        if shouldClose {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onClose()
                        } else {
                            withAnimation(.smooth(duration: 0.18, extraBounce: 0.0)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .onChange(of: isContentVisible) { _, visible in
                if visible == false {
                    dragOffset = 0
                }
            }
        }
    }

    private var overlayArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            if let artworkImage = song.artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 74, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BottomNavigationBar: View {
    let nowPlaying: DemoSong
    let isPlaying: Bool
    let isPlaybackLoading: Bool
    let namespace: Namespace.ID
    let isPlayerCardVisible: Bool
    let isDropTargeted: Bool
    @Binding var playerPillFrame: CGRect
    let onPlayerTap: () -> Void
    let onTogglePlayback: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var pillWidth: CGFloat {
        let title = isPlaybackLoading ? "歌曲加载中" : (isPlaying ? nowPlaying.title : "FlipMusic")
        let subtitle = isPlaybackLoading ? "" : (isPlaying ? nowPlaying.artist : "A simple way to listen music")
        let titleWidth = measuredTextWidth(title, size: 14, weight: .bold)
        let subtitleWidth = measuredTextWidth(subtitle, size: isPlaying ? 12 : 11, weight: .medium)
        let textWidth = max(titleWidth, subtitleWidth)
        let chromeWidth: CGFloat = 11 + 38 + 10 + 8 + 34 + 12
        return min(max(chromeWidth + textWidth + 8, 190), 356)
    }

    var body: some View {
        HStack {
            PlayerPill(
                song: nowPlaying,
                isPlaying: isPlaying,
                isPlaybackLoading: isPlaybackLoading,
                isActive: true,
                namespace: namespace,
                isPlayerCardVisible: isPlayerCardVisible,
                playerPillFrame: $playerPillFrame,
                action: onPlayerTap,
                onTogglePlayback: onTogglePlayback,
                onPrevious: onPrevious,
                onNext: onNext
            )
        }
        .frame(width: pillWidth)
        .scaleEffect(isDropTargeted ? 1.10 : 1)
        .animation(.smooth(duration: 0.18, extraBounce: 0.0), value: isDropTargeted)
        .animation(.bouncy(duration: 0.48, extraBounce: 0.18), value: pillWidth)
        .animation(.easeInOut(duration: 0.18), value: isPlaybackLoading)
    }

    private func measuredTextWidth(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

private struct MusicSparkleField: View {
    let song: DemoSong
    @State private var particles: [MusicParticleSpec] = []

    private enum ParticleMood {
        case sparkle
        case square
        case triangle
    }

    private var rhythm: Double {
        song.rhythmEnergy
    }

    private var particleMood: ParticleMood {
        switch particleMoodIndex {
        case 1, 4:
            return .square
        case 2, 5:
            return .triangle
        default:
            return .sparkle
        }
    }

    private var particleMoodIndex: Int {
        let key = "\(song.title)|\(song.artist)"
        let folded = key.unicodeScalars.reduce(abs(song.id)) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return folded % 6
    }

    private var moodShapeShare: CGFloat {
        switch particleMood {
        case .sparkle:
            return 0.0
        case .square, .triangle:
            return 0.82
        }
    }

    private var sparkleCount: Int {
        Int(90 + rhythm * 70)
    }

    private var riseDuration: Double {
        8.2 - rhythm * 2.4
    }

    private var estimatedBPM: Double {
        72 + rhythm * 66
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let travelHeight = size.height * 1.02
                let baseY = size.height + 56
                let beatProgress = (time * estimatedBPM / 60).truncatingRemainder(dividingBy: 1)
                let beatPulse = exp(-beatProgress * 7)
                let offbeatPulse = exp(-abs(beatProgress - 0.5) * 7) * 0.18
                let pulse = min(0.42, beatPulse * 0.34 + offbeatPulse)

                for particle in particles {
                    let rawProgress = (time / particle.duration + particle.delay).truncatingRemainder(dividingBy: 1)
                    let easedProgress = rawProgress * (2 - rawProgress)
                    let vertical = max(0, 1 - rawProgress)
                    let verticalDensity = vertical * vertical
                    let fadeIn = min(rawProgress * 4.6, 1)
                    let fadeOut = min(vertical * 2.2, 1)
                    let alpha = min(
                        1.0,
                        fadeIn * fadeOut * particle.opacity * (0.78 + verticalDensity * 1.55 + pulse * 0.10)
                    )
                    guard alpha > 0.012 else { continue }

                    let drift = sin(time * particle.driftSpeed + particle.phase) * particle.driftAmount
                    let centerX = size.width * (particle.x + particle.birthScatter + particle.upperScatter * easedProgress) + drift
                    let centerY = baseY - easedProgress * travelHeight
                    let point = CGPoint(x: centerX, y: centerY)
                    drawParticle(in: &context, particle: particle, point: point, alpha: alpha, pulse: pulse)
                }
            }
        }
        .blendMode(.screen)
        .opacity(0.98)
        .onAppear {
            particles = makeParticles()
        }
        .onChange(of: song.id) { _, _ in
            particles = makeParticles()
        }
    }

    private func drawParticle(
        in context: inout GraphicsContext,
        particle: MusicParticleSpec,
        point: CGPoint,
        alpha: Double,
        pulse: Double
    ) {
        let radius = particle.radius
        let corePath = particlePath(style: particle.style, center: point, radius: radius)

        if particle.hasGlow {
            context.opacity = alpha * (0.28 + pulse * 0.02)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - radius * 1.20,
                    y: point.y - radius * 1.20,
                    width: radius * 2.40,
                    height: radius * 2.40
                )),
                with: .color(particle.tint.opacity(0.30))
            )
        }

        context.opacity = alpha * (particle.hasGlow ? 1.02 : 1.18)
        context.fill(corePath, with: .color(particle.coreTint.opacity(0.92)))
    }

    private func makeParticles() -> [MusicParticleSpec] {
        let mood = particleMood
        let shapeShare = moodShapeShare
        let count = sparkleCount
        let rhythm = rhythm
        return (0..<count).map { index in
            let seed = Double(index + 1)
            let shouldUseMoodShape = random(seed, 5.53) < shapeShare
            let style: MusicParticleSpec.Style
            if shouldUseMoodShape {
                switch mood {
                case .square:
                    style = random(seed, 7.91) > 0.52 ? .diamond : .square
                case .triangle:
                    style = .triangle
                case .sparkle:
                    style = .sparkle
                }
            } else if random(seed, 3.17) > 0.965 {
                style = .sparkle
            } else {
                style = .circle
            }

            let tint = particleTint(for: seed)
            let coreTint = random(seed, 12.4) > 0.68 ? tint : Color.white
            let radiusJitter = Double(random(seed, 2.41))
            let radiusScale = 1.10 + rhythm * 0.42 + Double(random(seed, 16.4)) * 0.58

            return MusicParticleSpec(
                x: random(seed, 1.13),
                birthScatter: (random(seed, 10.7) - 0.5) * (0.08 + rhythm * 0.12),
                upperScatter: (random(seed, 9.51) - 0.5) * (0.32 + rhythm * 0.18),
                delay: Double(random(seed, 0.31)) * 1.24,
                duration: max(3.6, riseDuration + Double(random(seed, 0.73)) * 2.10),
                driftAmount: 5 + random(seed, 4.83) * 10,
                driftSpeed: 0.08 + Double(random(seed, 6.21)) * 0.18,
                phase: Double(random(seed, 8.41)) * .pi * 2,
                radius: CGFloat(0.42 + radiusJitter * radiusScale),
                opacity: 0.42 + Double(random(seed, 11.19)) * 0.58,
                tint: tint,
                coreTint: coreTint,
                style: style,
                hasGlow: random(seed, 13.63) > 0.76
            )
        }
    }

    private func particleTint(for seed: Double) -> Color {
        let pick = random(seed, 8.19)
        if pick < 0.18 {
            return Color(red: 0.62, green: 0.86, blue: 1.0)
        } else if pick < 0.34 {
            return Color(red: 1.0, green: 0.82, blue: 0.58)
        } else if pick < 0.48 {
            return Color(red: 0.82, green: 0.72, blue: 1.0)
        } else if pick < 0.60 {
            return Color(red: 0.72, green: 1.0, blue: 0.90)
        }

        guard song.colors.isEmpty == false else {
            return song.magicColor
        }
        let colorIndex = min(
            song.colors.count - 1,
            Int(Double(song.colors.count) * Double(random(seed, 12.83)))
        )
        return song.colors[colorIndex]
    }

    private func random(_ seed: Double, _ salt: Double) -> CGFloat {
        let value = sin((seed + salt) * 12.9898) * 43758.5453
        return CGFloat(value - floor(value))
    }

    private func particlePath(style: MusicParticleSpec.Style, center: CGPoint, radius: CGFloat) -> Path {
        switch style {
        case .circle:
            return Path(ellipseIn: CGRect(
                x: center.x - radius * 0.50,
                y: center.y - radius * 0.50,
                width: radius,
                height: radius
            ))
        case .square:
            let side = radius * 1.18
            return Path(CGRect(x: center.x - side * 0.5, y: center.y - side * 0.5, width: side, height: side))
        case .diamond:
            let side = radius * 1.20
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: center.y - side * 0.62))
            path.addLine(to: CGPoint(x: center.x + side * 0.62, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + side * 0.62))
            path.addLine(to: CGPoint(x: center.x - side * 0.62, y: center.y))
            path.closeSubpath()
            return path
        case .triangle:
            let side = radius * 1.46
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: center.y - side * 0.62))
            path.addLine(to: CGPoint(x: center.x + side * 0.58, y: center.y + side * 0.42))
            path.addLine(to: CGPoint(x: center.x - side * 0.58, y: center.y + side * 0.42))
            path.closeSubpath()
            return path
        case .sparkle:
            return sparklePath(center: center, radius: radius * 1.35)
        }
    }

    private func sparklePath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius * 0.25, y: center.y - radius * 0.25))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x + radius * 0.25, y: center.y + radius * 0.25))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius * 0.25, y: center.y + radius * 0.25))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.25))
        path.closeSubpath()
        return path
    }
}

private struct MusicParticleSpec {
    enum Style {
        case circle
        case square
        case diamond
        case triangle
        case sparkle
    }

    let x: CGFloat
    let birthScatter: CGFloat
    let upperScatter: CGFloat
    let delay: Double
    let duration: Double
    let driftAmount: CGFloat
    let driftSpeed: Double
    let phase: Double
    let radius: CGFloat
    let opacity: Double
    let tint: Color
    let coreTint: Color
    let style: Style
    let hasGlow: Bool
}

private struct CarouselPlayerOverlay: View {
    let songs: [DemoSong]
    @Binding var nowPlaying: DemoSong
    let isPlaying: Bool
    let isContentVisible: Bool
    let onClose: () -> Void
    let onTogglePlayback: () -> Void
    let onSongChange: (DemoSong) -> Void

    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let coverSide = min(max(proxy.size.width * 0.48, 210), 330)
            let centerY = proxy.size.height * 0.42

            ZStack {
                ForEach(visibleOffsets, id: \.self) { relativeOffset in
                    if let song = song(atRelativeOffset: relativeOffset) {
                        carouselCover(
                            song: song,
                            relativeOffset: relativeOffset,
                            coverSide: coverSide,
                            centerY: centerY,
                            width: proxy.size.width
                        )
                    }
                }

                VStack(spacing: 18) {
                    Spacer()

                    HStack(spacing: 22) {
                        carouselControl("backward.end.fill", isEnabled: hasPrevious) {
                            move(by: -1)
                        }

                        Button(action: onTogglePlayback) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 26, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(.black.opacity(0.86))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.32), radius: 16, y: 8)
                        }
                        .buttonStyle(.plain)

                        carouselControl("forward.end.fill", isEnabled: hasNext) {
                            move(by: 1)
                        }
                    }

                    Text(playerDescription(for: currentSong))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: min(proxy.size.width - 70, 420))
                        .padding(.bottom, safeBottom + 34)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.34))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .position(x: proxy.size.width - 34, y: safeTop + 34)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isContentVisible ? 1 : 0)
            .scaleEffect(isContentVisible ? 1 : 0.98)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let threshold = proxy.size.width * 0.18
                        if value.translation.width < -threshold || value.predictedEndTranslation.width < -threshold * 1.6 {
                            move(by: 1)
                        } else if value.translation.width > threshold || value.predictedEndTranslation.width > threshold * 1.6 {
                            move(by: -1)
                        }
                        withAnimation(.smooth(duration: 0.18, extraBounce: 0.0)) {
                            dragOffset = 0
                        }
                    }
            )
            .onAppear {
                currentIndex = indexForNowPlaying()
                PlayerArtworkWarmupCache.shared.preload(songs: Array(songs.prefix(12)))
            }
            .onChange(of: nowPlaying.id) { _, _ in
                currentIndex = indexForNowPlaying()
                preloadNearbyArtwork()
            }
            .onChange(of: songs.count) { _, _ in
                currentIndex = min(indexForNowPlaying(), max(songs.count - 1, 0))
                preloadNearbyArtwork()
            }
        }
    }

    private var visibleOffsets: [Int] {
        [-3, -2, -1, 0, 1, 2, 3]
    }

    private var currentSong: DemoSong {
        guard songs.indices.contains(currentIndex) else { return nowPlaying }
        return songs[currentIndex]
    }

    private var hasPrevious: Bool {
        currentIndex > 0
    }

    private var hasNext: Bool {
        currentIndex < songs.count - 1
    }

    private func song(atRelativeOffset offset: Int) -> DemoSong? {
        let index = currentIndex + offset
        guard songs.indices.contains(index) else { return nil }
        return songs[index]
    }

    private func carouselCover(
        song: DemoSong,
        relativeOffset: Int,
        coverSide: CGFloat,
        centerY: CGFloat,
        width: CGFloat
    ) -> some View {
        let absoluteOffset = abs(relativeOffset)
        let dragAngle = Double(dragOffset / max(width, 1)) * 44
        let angle = Double(relativeOffset) * 28 - dragAngle
        let angleRadians = angle * .pi / 180
        let radiusX = coverSide * 1.28
        let radiusY = coverSide * 0.16
        let xOffset = sin(angleRadians) * radiusX + dragOffset
        let depth = (1 - cos(angleRadians))
        let scale = relativeOffset == 0 ? 1.0 : max(0.40, 1.0 - CGFloat(depth) * 0.50 - CGFloat(absoluteOffset) * 0.05)
        let opacity = relativeOffset == 0 ? 1.0 : max(0.25, 0.88 - depth * 0.48 - Double(absoluteOffset) * 0.05)
        let rotation = -angle
        let yOffset = CGFloat(depth) * radiusY + CGFloat(absoluteOffset) * 3

        return PlayerSquareArtwork(song: song)
            .frame(width: coverSide, height: coverSide)
            .clipShape(RoundedRectangle(cornerRadius: relativeOffset == 0 ? 24 : 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: relativeOffset == 0 ? 24 : 18, style: .continuous)
                    .stroke(.white.opacity(relativeOffset == 0 ? 0.18 : 0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(relativeOffset == 0 ? 0.38 : 0.18), radius: relativeOffset == 0 ? 26 : 12, y: 12)
            .scaleEffect(scale)
            .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
            .offset(x: xOffset, y: yOffset)
            .position(x: width / 2, y: centerY)
            .opacity(opacity)
            .zIndex(Double(10 - absoluteOffset))
            .onTapGesture {
                if relativeOffset == 0 {
                    onTogglePlayback()
                } else {
                    move(by: relativeOffset)
                }
            }
    }

    private func carouselControl(_ systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.22))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func move(by step: Int) {
        guard songs.isEmpty == false else { return }
        let nextIndex = min(max(currentIndex + step, 0), songs.count - 1)
        guard nextIndex != currentIndex else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.02)) {
            currentIndex = nextIndex
        }
        let song = songs[nextIndex]
        nowPlaying = song
        preloadNearbyArtwork()
        onSongChange(song)
    }

    private func indexForNowPlaying() -> Int {
        songs.firstIndex(where: { $0.id == nowPlaying.id }) ?? 0
    }

    private func preloadNearbyArtwork() {
        guard songs.isEmpty == false else { return }
        let lower = max(currentIndex - 3, 0)
        let upper = min(currentIndex + 5, songs.count - 1)
        PlayerArtworkWarmupCache.shared.preload(songs: Array(songs[lower...upper]))
    }

    private func playerDescription(for song: DemoSong) -> String {
        let titleText = "\(song.title) \(song.artist)".lowercased()
        if titleText.contains("hip") || titleText.contains("rap") {
            return "Conscious hip hop with sharp rhythm, warm texture, and forward motion"
        }
        if titleText.contains("dance") || titleText.contains("club") || titleText.contains("dua") {
            return "Polished dance pop with bright hooks and clean late-night momentum"
        }
        if titleText.contains("soundtrack") || titleText.contains("score") {
            return "Cinematic detail, wide dynamics, and a spacious emotional arc"
        }
        if titleText.contains("r&b") || titleText.contains("weeknd") {
            return "Smooth R&B color with soft pressure, glossy space, and slow burn"
        }
        return "A focused listen with rich color, clear movement, and an easy repeat feel"
    }
}

private struct PlayerSquareArtwork: View {
    let song: DemoSong

    var body: some View {
        SongSquare(song: song, isPlaying: false)
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
    let onTogglePlayback: (DemoSong) -> Void
    let onSongChange: (DemoSong) -> Void
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var pendingSongChangeTask: Task<Void, Never>?
    private let cardSpacing: CGFloat = 10

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                let pageHeight = max(proxy.size.height - 54, 520)
                let pageStride = pageHeight + cardSpacing

                ZStack(alignment: .top) {
                    if let previousSong {
                        adjacentPlayerCard(song: previousSong, pageHeight: pageHeight)
                            .offset(y: -pageStride + dragOffset)
                            .opacity(dragOffset > 4 ? 1 : 0)
                            .zIndex(1)
                            .allowsHitTesting(false)
                    }

                    if let nextSong {
                        adjacentPlayerCard(song: nextSong, pageHeight: pageHeight)
                            .offset(y: pageStride + dragOffset)
                            .zIndex(1)
                            .allowsHitTesting(false)
                    }

                    if let song = currentSong {
                        playerCard(song: song, pageHeight: pageHeight)
                            .id(song.id)
                            .offset(y: dragOffset)
                            .zIndex(3)
                            .allowsHitTesting(true)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .local)
                        .onChanged { value in
                            guard isContentVisible else { return }
                            let nextOffset = boundedDragOffset(value.translation.height, pageHeight: pageHeight)
                            guard abs(nextOffset - dragOffset) > 1.4 else { return }
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                dragOffset = nextOffset
                            }
                        }
                        .onEnded { value in
                            guard isContentVisible else { return }
                            finishDrag(value, pageHeight: pageHeight)
                        }
                )
            }
            .opacity(isContentVisible ? 1 : 0)
            .scaleEffect(isContentVisible ? 1 : 0.98)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .onAppear {
            currentIndex = indexForNowPlaying()
            preloadUpcomingArtwork()
        }
        .onChange(of: nowPlaying.id) { _, newID in
            guard let newIndex = songs.firstIndex(where: { $0.id == newID }) else { return }
            guard newIndex != currentIndex else { return }
            guard abs(dragOffset) < 1 else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentIndex = newIndex
                dragOffset = 0
            }
            preloadUpcomingArtwork(startingAt: newIndex)
        }
        .onChange(of: songs.count) { _, _ in
            let newIndex = min(indexForNowPlaying(), max(songs.count - 1, 0))
            currentIndex = newIndex
            dragOffset = 0
            preloadUpcomingArtwork(startingAt: newIndex)
        }
        .onDisappear {
            pendingSongChangeTask?.cancel()
        }
    }

    private func indexForNowPlaying() -> Int {
        songs.firstIndex(where: { $0.id == nowPlaying.id }) ?? 0
    }

    private func playerCard(song: DemoSong, pageHeight: CGFloat) -> some View {
        NowPlayingCard(
            song: song,
            isActive: song.id == currentSong?.id,
            isPlaying: isPlaybackActive(song),
            onClose: onClose,
            onTogglePlayback: {
                onTogglePlayback(song)
            }
        )
        .frame(height: pageHeight)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func adjacentPlayerCard(song: DemoSong, pageHeight: CGFloat) -> some View {
        AdjacentPlayerPreviewCard(song: song)
            .frame(height: pageHeight)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .transaction { transaction in
                transaction.animation = nil
            }
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
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.02)) {
            dragOffset = exitOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentIndex = nextIndex
                nowPlaying = song
                dragOffset = 0
            }
            preloadUpcomingArtwork(startingAt: nextIndex)
        }
        schedulePlayback(for: song)
    }

    private func preloadUpcomingArtwork(startingAt index: Int? = nil) {
        let startIndex = index ?? currentIndex
        guard songs.indices.contains(startIndex) else { return }
        let endIndex = min(startIndex + 5, songs.count - 1)
        let preloadSongs = Array(songs[startIndex...endIndex])
        PlayerArtworkWarmupCache.shared.preload(songs: preloadSongs)
    }

    private func schedulePlayback(for song: DemoSong) {
        pendingSongChangeTask?.cancel()
        pendingSongChangeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
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
            NowPlayingVisual(song: song, isPlaying: isPlaying, width: proxy.size.width)
                .equatable()
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTogglePlayback()
            }
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

private struct NowPlayingVisual: View, Equatable {
    let song: DemoSong
    let isPlaying: Bool
    let width: CGFloat

    static func == (lhs: NowPlayingVisual, rhs: NowPlayingVisual) -> Bool {
        lhs.song.id == rhs.song.id &&
        lhs.isPlaying == rhs.isPlaying &&
        abs(lhs.width - rhs.width) < 0.5
    }

    var body: some View {
        let side = max(width, 220)

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
                .padding(.bottom, 74)
            }

            if !isPlaying {
                Color.black.opacity(0.18)
                    .allowsHitTesting(false)

                RoundedPlayTriangle(cornerRadius: 10)
                    .fill(.white.opacity(0.60))
                    .frame(width: 54, height: 62)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isPlaying)
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

                if let image = PlayerArtworkWarmupCache.shared.artwork(for: song) ?? song.artworkImage {
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

private struct PlayerNextPeek: View {
    let song: DemoSong

    var body: some View {
        ZStack {
            song.magicColor
                .opacity(0.72)

            if let image = PlayerArtworkWarmupCache.shared.artwork(for: song) ?? song.artworkImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.38)
                    .clipped()
            }

            LinearGradient(
                colors: [.white.opacity(0.08), .black.opacity(0.20)],
                startPoint: .top,
                endPoint: .bottom
            )
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

                LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

                song.magicColor
                    .opacity(0.34)

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

            if let artworkImage = PlayerArtworkWarmupCache.shared.artwork(for: song) ?? song.artworkImage {
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

private final class PlayerArtworkWarmupCache {
    static let shared = PlayerArtworkWarmupCache()

    private let artworkCache = NSCache<NSNumber, UIImage>()
    private var warmingIDs = Set<Int>()

    private init() {
        artworkCache.countLimit = 80
    }

    func artwork(for song: DemoSong) -> UIImage? {
        artworkCache.object(forKey: NSNumber(value: song.id))
    }

    func preload(songs: [DemoSong]) {
        let targets = songs.filter { song in
            artworkCache.object(forKey: NSNumber(value: song.id)) == nil &&
            warmingIDs.contains(song.id) == false
        }
        guard targets.isEmpty == false else { return }
        targets.forEach { warmingIDs.insert($0.id) }

        Task.detached(priority: .utility) { [weak self] in
            var preparedImages: [(Int, UIImage)] = []
            for song in targets {
                if let preparedArtwork = await song.artworkImage?.byPreparingForDisplay() {
                    preparedImages.append((song.id, preparedArtwork))
                }
            }

            await MainActor.run {
                preparedImages.forEach { id, image in
                    self?.artworkCache.setObject(image, forKey: NSNumber(value: id))
                }
                targets.forEach { self?.warmingIDs.remove($0.id) }
            }
        }
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

private struct TopSettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerPill: View {
    let song: DemoSong
    let isPlaying: Bool
    let isPlaybackLoading: Bool
    let isActive: Bool
    let namespace: Namespace.ID
    let isPlayerCardVisible: Bool
    @Binding var playerPillFrame: CGRect
    let action: () -> Void
    let onTogglePlayback: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    @GestureState private var dragTranslation: CGFloat = 0
    @State private var committedArtworkOffset: CGFloat = 0
    @State private var isTextVisible = true

    private var boundedDragOffset: CGFloat {
        max(-96, min(96, dragTranslation))
    }

    private var artworkOffset: CGFloat {
        committedArtworkOffset + boundedDragOffset
    }

    var body: some View {
        ZStack {
            PlayerPillGlassBackground(song: song, isActive: isActive)

            HStack(spacing: 10) {
                RotatingAlbumArt(song: song, isSpinning: isPlaying)
                    .offset(x: artworkOffset)
                    .opacity(max(0.18, 1 - abs(artworkOffset) / 92))
                    .scaleEffect(1 - min(abs(artworkOffset) / 260, 0.10))
                    .animation(.smooth(duration: 0.16, extraBounce: 0.0), value: committedArtworkOffset)
                    .animation(.smooth(duration: 0.12, extraBounce: 0.0), value: dragTranslation)

                PlayerPillSongText(song: song, isPlaying: isPlaying, isLoading: isPlaybackLoading)
                    .id(song.id)
                    .opacity(isTextVisible ? max(0.18, 1 - abs(boundedDragOffset) / 120) : 0)
                    .offset(x: boundedDragOffset * 0.18)
                    .animation(.easeInOut(duration: 0.16), value: isTextVisible)
                    .animation(.smooth(duration: 0.12, extraBounce: 0.0), value: dragTranslation)
                .contentShape(Rectangle())

                Spacer(minLength: 8)

                Button(action: onTogglePlayback) {
                    PlayerPillPlaybackButtonIcon(
                        isPlaying: isPlaying,
                        isLoading: isPlaybackLoading
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPlaybackLoading)
            }
            .padding(.leading, 11)
            .padding(.trailing, 12)
            .opacity(isPlayerCardVisible ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 53)
        .background {
            PlayerPillGlassAura(song: song, isActive: isActive)
        }
        .clipShape(RoundedRectangle(cornerRadius: 27))
        .overlay {
            RoundedRectangle(cornerRadius: 27)
                .stroke(.white.opacity(isActive ? 0.18 : 0.10), lineWidth: 0.8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 27)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.30),
                            .white.opacity(0.08),
                            song.magicColor.opacity(0.14),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .mask(
                    LinearGradient(
                        colors: [.black, .black.opacity(0.72), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .shadow(color: .white.opacity(0.06), radius: 14, y: -5)
        .shadow(color: song.magicColor.opacity(0.12), radius: 18, y: 6)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 9)
        .contentShape(RoundedRectangle(cornerRadius: 27))
        .onTapGesture(perform: action)
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    finishSwipe(value)
                }
        )
        .liquidGlassSurface(cornerRadius: 27, isInteractive: true)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: PlayerPillFramePreferenceKey.self, value: proxy.frame(in: .named("contentRoot")))
            }
        }
        .onPreferenceChange(PlayerPillFramePreferenceKey.self) { frame in
            playerPillFrame = frame
        }
        .onChange(of: song.id) { _, _ in
            isTextVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeOut(duration: 0.18)) {
                    isTextVisible = true
                }
            }
        }
        .opacity(isPlayerCardVisible ? 0 : 1)
    }

    private func finishSwipe(_ value: DragGesture.Value) {
        let threshold: CGFloat = 64
        let predicted = value.predictedEndTranslation.width
        let translation = value.translation.width
        let shouldGoNext = translation < -threshold || predicted < -threshold * 1.45
        let shouldGoPrevious = translation > threshold || predicted > threshold * 1.45

        guard shouldGoNext || shouldGoPrevious else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.32)
            withAnimation(.smooth(duration: 0.16, extraBounce: 0.0)) {
                committedArtworkOffset = 0
                isTextVisible = true
            }
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.58)
        let direction: CGFloat = shouldGoNext ? -1 : 1
        withAnimation(.easeOut(duration: 0.12)) {
            committedArtworkOffset = direction * 96
            isTextVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if shouldGoNext {
                onNext()
            } else {
                onPrevious()
            }
            committedArtworkOffset = -direction * 42
            withAnimation(.smooth(duration: 0.18, extraBounce: 0.0)) {
                committedArtworkOffset = 0
                isTextVisible = true
            }
        }
    }
}

private struct PlayerPillGlassBackground: View {
    let song: DemoSong
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 27, style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(0.20)
            .overlay {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(.black.opacity(0.36))
            }
            .overlay {
                LinearGradient(
                    colors: [
                        .white.opacity(0.055),
                        .white.opacity(0.018),
                        .black.opacity(0.10),
                        song.magicColor.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.14), location: 0.00),
                        .init(color: .white.opacity(0.025), location: 0.22),
                        .init(color: song.magicColor.opacity(isActive ? 0.10 : 0.07), location: 0.58),
                        .init(color: song.magicColor.opacity(isActive ? 0.16 : 0.10), location: 0.82),
                        .init(color: .black.opacity(0.08), location: 1.00)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.24),
                                .white.opacity(0.08),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1.6)
                    .padding(.horizontal, 16)
                    .padding(.top, 1.5)
                    .blur(radius: 0.25)
            }
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(width: 88, height: 20)
                    .rotationEffect(.degrees(-14))
                    .offset(x: 22, y: 8)
                    .blur(radius: 9)
                    .blendMode(.screen)
            }
            .overlay(alignment: .bottomTrailing) {
                Capsule()
                    .fill(song.magicColor.opacity(0.14))
                    .frame(width: 136, height: 26)
                    .rotationEffect(.degrees(-12))
                    .offset(x: -24, y: -7)
                    .blur(radius: 13)
                    .blendMode(.screen)
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(song.magicColor.opacity(0.08))
                    .frame(width: 90, height: 38)
                    .offset(x: -26)
                    .blur(radius: 18)
                    .blendMode(.screen)
            }
    }
}

private struct PlayerPillGlassAura: View {
    let song: DemoSong
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(.white.opacity(isActive ? 0.16 : 0.10), lineWidth: 2)
                .blur(radius: 8)
                .opacity(0.82)

            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(song.magicColor.opacity(isActive ? 0.24 : 0.16), lineWidth: 7)
                .blur(radius: 18)
                .opacity(0.64)

            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(song.magicColor.opacity(isActive ? 0.12 : 0.08), lineWidth: 12)
                .blur(radius: 28)
                .opacity(0.55)
        }
        .padding(-8)
        .allowsHitTesting(false)
    }
}

private struct PlayerPillPlaybackButtonIcon: View {
    let isPlaying: Bool
    let isLoading: Bool

    var body: some View {
        ZStack {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(isLoading ? 0.72 : 1)
                .opacity(isLoading ? 0 : 1)

            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .controlSize(.small)
                .scaleEffect(isLoading ? 0.92 : 0.68)
                .opacity(isLoading ? 1 : 0)
        }
        .frame(width: 34, height: 38)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.16), value: isLoading)
        .animation(.easeInOut(duration: 0.16), value: isPlaying)
    }
}

private struct PlayerPillSongText: View {
    let song: DemoSong
    let isPlaying: Bool
    let isLoading: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isPlaying ? song.title : "FlipMusic")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(isPlaying ? song.artist : "A simple way to listen music")
                    .font(.system(size: isPlaying ? 12 : 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
            .opacity(isLoading ? 0 : 1)
            .scaleEffect(isLoading ? 0.98 : 1, anchor: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("歌曲加载中")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text(" ")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .opacity(isLoading ? 1 : 0)
            .scaleEffect(isLoading ? 1 : 0.98, anchor: .leading)
        }
        .animation(.easeInOut(duration: 0.18), value: isLoading)
        .animation(.easeInOut(duration: 0.18), value: isPlaying)
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
                self.glassEffect(.regular.tint(.black.opacity(0.18)).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular.tint(.white.opacity(0.055)), in: .rect(cornerRadius: cornerRadius))
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
                    .opacity(0.52)
                    .mask(
                        LinearGradient(
                            colors: [
                                .clear,
                                .black.opacity(0.10),
                                .black.opacity(0.30),
                                .black.opacity(0.48),
                                .black.opacity(0.62)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                LinearGradient(
                    colors: [
                        background.opacity(0.0),
                        background.opacity(0.06),
                        background.opacity(0.15),
                        background.opacity(0.26),
                        background.opacity(0.38),
                        background.opacity(0.50),
                        background.opacity(0.58)
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

private enum ITunesSearchClient {
    static func search(term: String, limit: Int) async throws -> [ITunesTrack] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: AppleMusicStorefront.current),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components?.url else { return [] }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        return response.results
    }

    static func artworkImage(from urlString: String?) async -> UIImage? {
        guard let urlString,
              let url = URL(string: urlString.replacingOccurrences(of: "100x100bb", with: "600x600bb")) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

private enum AppleMusicRSSClient {
    static func topSongs(limit: Int) async throws -> [ITunesTrack] {
        let safeLimit = min(max(limit, 10), 50)
        let urlString = "https://rss.marketingtools.apple.com/api/v2/\(AppleMusicStorefront.current)/music/most-played/\(safeLimit)/songs.json"
        guard let url = URL(string: urlString) else { return [] }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(AppleMusicRSSResponse.self, from: data)
        return response.feed.results
    }
}

private enum LRCLibClient {
    static func lyrics(title: String, artist: String) async throws -> String? {
        if let exactLyrics = try await getLyrics(title: title, artist: artist) {
            return exactLyrics
        }
        return try await searchLyrics(title: title, artist: artist)
    }

    private static func getLyrics(title: String, artist: String) async throws -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = components?.url else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        let payload = try JSONDecoder().decode(LRCLibTrack.self, from: data)
        return payload.plainLyrics ?? payload.syncedLyrics
    }

    private static func searchLyrics(title: String, artist: String) async throws -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "\(artist) \(title)"),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        guard let url = components?.url else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        let payload = try JSONDecoder().decode([LRCLibTrack].self, from: data)
        let bestMatch = payload.first { candidate in
            normalized(candidate.trackName) == normalized(title) &&
            normalized(candidate.artistName) == normalized(artist)
        } ?? payload.first

        return bestMatch?.plainLyrics ?? bestMatch?.syncedLyrics
    }

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum LyricsOVHClient {
    static func lyrics(title: String, artist: String) async throws -> String? {
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        guard let encodedArtist, let encodedTitle,
              let url = URL(string: "https://api.lyrics.ovh/v1/\(encodedArtist)/\(encodedTitle)") else {
            return nil
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        let payload = try JSONDecoder().decode(LyricsOVHResponse.self, from: data)
        return payload.lyrics
    }
}

private enum AppleMusicStorefront {
    static var current: String {
        Locale.current.region?.identifier.lowercased() ?? "cn"
    }
}

private struct ITunesSearchResponse: Decodable {
    let results: [ITunesTrack]
}

private struct AppleMusicRSSResponse: Decodable {
    let feed: AppleMusicRSSFeed
}

private struct AppleMusicRSSFeed: Decodable {
    let results: [ITunesTrack]
}

private struct LRCLibTrack: Decodable {
    let trackName: String
    let artistName: String
    let plainLyrics: String?
    let syncedLyrics: String?
}

private struct LyricsOVHResponse: Decodable {
    let lyrics: String
}

private struct ITunesTrack: Decodable {
    let trackID: String
    let trackName: String
    let artistName: String
    let artworkURL100: String?
    let releaseDate: Date?

    private enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case id
        case trackName
        case name
        case artistName
        case artworkURL100 = "artworkUrl100"
        case releaseDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let numericID = try? container.decode(Int.self, forKey: .trackID) {
            trackID = String(numericID)
        } else if let stringID = try? container.decode(String.self, forKey: .trackID) {
            trackID = stringID
        } else {
            trackID = try container.decode(String.self, forKey: .id)
        }
        if let trackName = try? container.decode(String.self, forKey: .trackName) {
            self.trackName = trackName
        } else {
            self.trackName = try container.decode(String.self, forKey: .name)
        }
        artistName = try container.decode(String.self, forKey: .artistName)
        artworkURL100 = try container.decodeIfPresent(String.self, forKey: .artworkURL100)
        if let releaseDateString = try container.decodeIfPresent(String.self, forKey: .releaseDate) {
            releaseDate = ISO8601DateFormatter().date(from: releaseDateString)
        } else {
            releaseDate = nil
        }
    }
}

private extension Array where Element == ITunesTrack {
    var prioritizingRecentReleases: [ITunesTrack] {
        sorted { lhs, rhs in
            switch (lhs.releaseDate, rhs.releaseDate) {
            case let (lhsDate?, rhsDate?):
                if lhsDate == rhsDate { return lhs.trackName < rhs.trackName }
                return lhsDate > rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.trackName < rhs.trackName
            }
        }
    }
}

private extension MPMediaItem {
    var safePlaybackStoreID: String? {
        let id = playbackStoreID
        return id.isEmpty ? nil : id
    }
}

private struct DemoSong: Identifiable {
    let id: Int
    let title: String
    let artist: String
    let colors: [Color]
    let mediaItem: MPMediaItem?
    let storeID: String?
    let artworkImage: UIImage?
    let backdropImage: UIImage?
    let lyricsText: String?
    let magicColor: Color
    let source: DemoSongSource

    init(
        id: Int,
        title: String,
        artist: String,
        colors: [Color],
        mediaItem: MPMediaItem? = nil,
        storeID: String? = nil,
        artworkImage: UIImage? = nil,
        backdropImage: UIImage? = nil,
        lyricsText: String? = nil,
        magicColor: Color? = nil,
        source: DemoSongSource = .demo
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.colors = colors
        self.mediaItem = mediaItem
        self.storeID = storeID
        self.artworkImage = artworkImage
        self.backdropImage = backdropImage
        self.lyricsText = lyricsText
        self.magicColor = magicColor ?? colors.first ?? .black
        self.source = source
    }

    var isPlayable: Bool {
        mediaItem != nil || storeID != nil
    }

    var isPlaceholder: Bool {
        source == .placeholder
    }

    var rhythmEnergy: Double {
        let text = "\(title) \(artist)".lowercased()
        let fastWords = [
            "dance", "rush", "club", "party", "desire", "kiss", "greedy", "hot",
            "energy", "run", "move", "night", "pop", "beat", "speed", "jump"
        ]
        let slowWords = [
            "slow", "sleep", "dream", "tears", "ocean", "eyes", "flower",
            "ballad", "blue", "alone", "sad", "soft", "quiet"
        ]
        let keywordBoost = fastWords.contains { text.contains($0) } ? 0.22 : 0
        let slowPenalty = slowWords.contains { text.contains($0) } ? 0.16 : 0
        let colorEnergy = colors.reduce(0.0) { partial, color in
            let resolved = color.resolve(in: EnvironmentValues())
            let red = Double(resolved.red)
            let green = Double(resolved.green)
            let blue = Double(resolved.blue)
            let brightness = max(red, green, blue)
            let saturation = brightness == 0 ? 0 : (brightness - min(red, green, blue)) / brightness
            return partial + brightness * 0.36 + saturation * 0.44
        } / Double(max(colors.count, 1))
        return min(max(0.28 + colorEnergy + keywordBoost - slowPenalty, 0.18), 1.0)
    }

    static func placeholder(id: Int, colors: [Color]) -> DemoSong {
        let morandiColors: [[Color]] = [
            [Color(red: 0.58, green: 0.64, blue: 0.60), Color(red: 0.42, green: 0.49, blue: 0.53)],
            [Color(red: 0.67, green: 0.57, blue: 0.52), Color(red: 0.48, green: 0.42, blue: 0.47)],
            [Color(red: 0.55, green: 0.58, blue: 0.68), Color(red: 0.39, green: 0.45, blue: 0.57)],
            [Color(red: 0.66, green: 0.62, blue: 0.50), Color(red: 0.48, green: 0.53, blue: 0.44)],
            [Color(red: 0.62, green: 0.50, blue: 0.56), Color(red: 0.43, green: 0.45, blue: 0.55)],
            [Color(red: 0.50, green: 0.61, blue: 0.62), Color(red: 0.38, green: 0.49, blue: 0.50)]
        ]
        let palette = morandiColors[abs(id) % morandiColors.count]
        return DemoSong(
            id: id,
            title: "",
            artist: "",
            colors: palette,
            magicColor: palette.first,
            source: .placeholder
        )
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

private enum DemoSongSource {
    case demo
    case library
    case recommendation
    case spotify
    case placeholder
}

private struct HomeInteractiveSongSquare: View {
    let frontSong: DemoSong
    let backSong: DemoSong
    let displayedSong: DemoSong
    let isPlaying: Bool
    let progress: CGFloat
    let variation: HomeFlipVariation
    let onTap: () -> Void

    var body: some View {
        GeometryReader { _ in
            HomeFlipSongSquare(
                frontSong: frontSong,
                backSong: backSong,
                isPlaying: isPlaying,
                progress: progress,
                variation: variation
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(perform: onTap)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
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
