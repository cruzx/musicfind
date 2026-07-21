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
import AVFoundation
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
    @State private var homeFlipVariations: [Int: HomeFlipVariation] = [:]
    @State private var homeFlippingIndices: Set<Int> = []
    @State private var homeAppearingFlipIndices: Set<Int> = []
    @State private var isHomeFlipping = false
    @State private var homeFlipGeneration = UUID()
    @State private var isHomeLoadingMore = false
    @State private var isHomeAppendingMore = false
    @State private var homeLoadMorePage = 0
    @State private var homeAutoFillTask: Task<Void, Never>?
    @State private var temporarilySkippedHomeSongIDs: [Int] = []
    @State private var recentlyShownHomeSongIDs: [Int] = []
    @State private var homeSessionSalt = Double.random(in: 0..<10_000)
    @State private var homeSourceSignature = ""
    @AppStorage("homeDislikedSongKeys") private var homeDislikedSongKeysRaw = ""
    @AppStorage("homeRecentlyShownSongKeys") private var homeRecentlyShownSongKeysRaw = ""
    @State private var pendingHomePlaybackTask: Task<Void, Never>?
    @State private var currentTimeMood = HomeTimeMood.current
    @StateObject private var shakeObserver = ShakeMotionObserver()
    private let timeMoodTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    @State private var homeIdleTask: Task<Void, Never>?
    @State private var homeFlipTask: Task<Void, Never>?
    @Namespace private var playerExpansionNamespace

    private let spacing: CGFloat = 8
    private var songs: [DemoSong] {
        let visibleSongs = musicConnector.homeSurfaceSongs.filter {
            $0.isHomeSurfacePlayable && isHomeSongDisliked($0) == false
        }
        if visibleSongs.isEmpty == false {
            return visibleSongs
        }

        return homeLoadingPlaceholders
    }

    private var homeLoadingPlaceholders: [DemoSong] {
        (0..<96).map { DemoSong.placeholder(id: -20_000 - $0, colors: []) }
    }
    private var homeSongSourceSignature: String {
        homeSourceSignature(for: songs)
    }
    private var visibleHomeSongs: [DemoSong] {
        homeSongs.isEmpty ? songs : homeSongs
    }
    private var isInitialLibraryLoadingVisible: Bool {
        if musicConnector.isInitialLibraryLoading {
            return true
        }
        return musicConnector.isConnectingAppleMusic ||
            musicConnector.isConnectingSpotify
    }
    private var settingsBackdropBlur: CGFloat {
        activeTab == .settings ? 16 : 0
    }
    private var playerBackdropBlur: CGFloat {
        isPlayerCardVisible ? 18 : 0
    }
    private var loadingBackdropBlur: CGFloat {
        isInitialLibraryLoadingVisible ? 24 : 0
    }
    private var sceneBackdropBlur: CGFloat {
        settingsBackdropBlur + playerBackdropBlur + loadingBackdropBlur
    }
    private var isPlaybackVisuallyActive: Bool {
        musicConnector.isPlaying || musicConnector.isPlaybackTransitioning
    }
    private var playerDisplaySong: DemoSong {
        musicConnector.currentSong ?? nowPlaying
    }
    private var nextPlayablePreviewSong: DemoSong? {
        musicConnector.queuedNeighbor(for: playerDisplaySong, step: 1, fallbackSongs: songs)
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
                                    gravity: homeCoverGravity(for: slot, columnCount: homeColumnCount),
                                    isFlipping: isHomeFlipping && homeFlippingIndices.contains(slot.id),
                                    isAppearing: homeAppearingFlipIndices.contains(slot.id),
                                    flipGeneration: homeFlipGeneration,
                                    variation: homeFlipVariations[slot.id] ?? .zero,
                                    onTap: {
                                        playHomeSong(slot.song)
                                    },
                                    onDislike: {
                                        dislikeHomeSong(slot.song)
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
            .blur(radius: sceneBackdropBlur, opaque: false)
            .scaleEffect(activeTab == .settings ? 0.985 : (isPlayerCardVisible ? 0.985 : 1))
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: activeTab)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: isPlayerCardVisible)
            .zIndex(0)

            TopGlassFade()
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .blur(radius: sceneBackdropBlur, opaque: false)
                .opacity(chromeOpacity)
                .zIndex(1)

            BottomGlassFade()
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .blur(radius: sceneBackdropBlur, opaque: false)
                .opacity(chromeOpacity)
                .zIndex(1)

            if isPlaybackVisuallyActive {
                MusicSparkleField(song: playerDisplaySong, preference: musicConnector.moodPreference)
                    .frame(width: proxy.size.width, height: min(proxy.size.height * 0.56, 520))
                    .offset(y: 74)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .blur(radius: sceneBackdropBlur, opaque: false)
                .transition(.opacity.animation(.easeOut(duration: 0.22)))
                .zIndex(4)
            }

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        if musicConnector.isPlaying {
                            HeaderNowPlayingBadge(song: playerDisplaySong)
                        } else {
                            GreetingBadge(mood: currentTimeMood)
                        }

                        if musicConnector.visibleSpotifySongCount > 0 {
                            SpotifyHomeSignal(songCount: musicConnector.visibleSpotifySongCount)
                        }
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
            .blur(radius: sceneBackdropBlur, opaque: false)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: activeTab)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: isPlayerCardVisible)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: isLandscape)
            .zIndex(6)

            VStack {
                Spacer()
                BottomNavigationBar(
                    nowPlaying: playerDisplaySong,
                    isPlaying: musicConnector.isPlaying,
                    isPlaybackLoading: musicConnector.isPlaybackTransitioning,
                    nextSong: nextPlayablePreviewSong,
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
                    },
                    onMoodSeek: { direction in
                        playMoodMatchedSong(direction: direction)
                    }
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .blur(radius: sceneBackdropBlur, opaque: false)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: activeTab)
            .animation(.smooth(duration: 0.24, extraBounce: 0.0), value: isPlayerCardVisible)
            .zIndex(8)

            if isInitialLibraryLoadingVisible {
                InitialLibraryLoadingOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }

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
            homeAutoFillTask?.cancel()
            homeAutoFillTask = nil
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
        .onChange(of: homeSongSourceSignature) { _, _ in
            guard isHomeAppendingMore == false else { return }
            syncHomeSongsIfNeeded()
            ensureHomeHasEnoughSongsIfNeeded()
        }
        .onChange(of: songs.map { "\($0.id):\($0.artworkImage != nil)" }) { _, _ in
            refreshVisibleHomeSongMetadata()
            ensureHomeHasEnoughSongsIfNeeded()
        }
        .onReceive(shakeObserver.$shakeEventID.dropFirst()) { _ in
            reshuffleHomeSongsWithFlip()
        }
        .onReceive(timeMoodTimer) { _ in
            updateTimeMoodIfNeeded()
        }
        .onChange(of: musicConnector.isConnectedToAnyMusicService) { _, isConnected in
            if isConnected {
                syncHomeSongsIfNeeded()
                ensureHomeHasEnoughSongsIfNeeded()
            } else {
                activeTab = .home
                isPlayerCardVisible = false
                isPlayerCardExpanded = false
                isPlayerCardContentVisible = false
            }
        }
    }

    private func playHomeSong(_ song: DemoSong) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        registerHomeInteraction()

        guard (song.isPlayable || song.source == .spotify), song.isPlaceholder == false else {
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
        let playbackPool = [song] + visibleHomeSongs + songs
        let playableSongs = playbackPool.filter { $0.isPlayable && $0.isPlaceholder == false }
        guard playableSongs.isEmpty == false else { return [song] }
        return playableSongs
    }

    private func toggleCurrentPlayback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let playbackSongs = songs
        Task { await musicConnector.togglePlayback(for: playerDisplaySong, in: playbackSongs) }
    }

    private func playAdjacentSong(step: Int) {
        guard let song = musicConnector.playQueuedNeighbor(from: playerDisplaySong, step: step, fallbackSongs: songs) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        nowPlaying = song
    }

    private func playMoodMatchedSong(direction: CGFloat) {
        let currentSong = playerDisplaySong
        let playbackSongs = songs.filter { $0.isPlayable && !$0.isPlaceholder && $0.id != currentSong.id }
        guard playbackSongs.isEmpty == false else { return }
        let wantsEnergy = direction > 0
        let mood = currentTimeMood
        let preference = musicConnector.moodPreference
        let targetEnergy = wantsEnergy ? min(1.0, 0.70 + preference.energy * 0.22) : max(0.08, 0.26 + preference.energy * 0.16)
        let chosen = playbackSongs
            .map { song -> (song: DemoSong, score: Double) in
                let energyFit = 1.0 - abs(song.rhythmEnergy - targetEnergy)
                let timeFit = mood.score(song) * 0.22
                let preferenceFit = preference.score(song) * 0.26
                return (song, energyFit + timeFit + preferenceFit + Double.random(in: 0...0.18))
            }
            .sorted { $0.score > $1.score }
            .first?.song

        guard let chosen else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
        nowPlaying = chosen
        musicConnector.queuePlayback(for: chosen, in: songs)
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

    private func homeCoverGravity(for slot: HomeSongSlot, columnCount: Int) -> HomeCoverGravity {
        guard musicConnector.isPlaying || musicConnector.isPlaybackTransitioning,
              visibleHomeSongs.contains(where: { $0.id == nowPlaying.id }) else {
            return .zero
        }

        let relation = coverRelationScore(slot.song, to: nowPlaying)
        return HomeCoverGravity(offset: .zero, scale: 1, glow: relation)
    }

    private func coverRelationScore(_ song: DemoSong, to target: DemoSong) -> CGFloat {
        guard song.id != target.id else { return 1 }
        var score: CGFloat = 0.18
        if song.artist == target.artist { score += 0.40 }
        if song.source == target.source { score += 0.12 }
        let leftWords = Set("\(song.title) \(song.artist)".lowercased().split(separator: " ").map(String.init))
        let rightWords = Set("\(target.title) \(target.artist)".lowercased().split(separator: " ").map(String.init))
        let overlap = leftWords.intersection(rightWords).filter { $0.count > 3 }.count
        score += CGFloat(min(overlap, 3)) * 0.09
        score += CGFloat(1 - abs(song.rhythmEnergy - target.rhythmEnergy)) * 0.18
        return min(1, score)
    }

    private func updateTimeMoodIfNeeded() {
        let latestMood = HomeTimeMood.current
        guard latestMood != currentTimeMood else { return }
        currentTimeMood = latestMood
        musicConnector.refreshRecommendationsForCurrentTime()
    }

    private func showPlayerCard() {
        guard !isPlayerCardVisible else { return }
        stopHomeDrift()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        activeTab = .player
        isPlayerCardContentVisible = false
        isPlayerCardDismissing = false
        isPlayerCardVisible = true
        musicConnector.loadLyricsIfNeeded(for: playerDisplaySong)
        ensureHomeHasEnoughSongsIfNeeded()

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
        return visibleHomeSongs[index]
    }

    private func syncHomeSongsIfNeeded() {
        let sourceSignature = homeSourceSignature(for: songs)
        if homeSongs.isEmpty {
            homeSourceSignature = sourceSignature
            homeSongs = initialHomeSongs()
            rememberRecentlyShownHomeSongs(homeSongs)
            PlayerArtworkWarmupCache.shared.preload(songs: Array(homeSongs.prefix(80)))
            resetHomeFlipState()
            ensureHomeHasEnoughSongsIfNeeded()
            return
        }

        refreshVisibleHomeSongMetadata()
        homeSongs = homeSongs.filter { isHomeSongDisliked($0) == false }
        homePendingSongs = homePendingSongs.filter { isHomeSongDisliked($0) == false }
        if sourceSignature != homeSourceSignature {
            homeSourceSignature = sourceSignature
            rebuildHomeSongsForRealDiscovery()
            return
        }
        if shouldRebuildHomeSongsForRealDiscovery() {
            rebuildHomeSongsForRealDiscovery()
            return
        }
        appendNewHomeSongsFromSource()
        ensureHomeHasEnoughSongsIfNeeded()
    }

    private func homeSourceSignature(for source: [DemoSong]) -> String {
        source.prefix(120).map { song in
            let hasArtwork = song.artworkImage == nil ? "0" : "1"
            return "\(song.id):\(song.title):\(song.artist):\(song.source):\(hasArtwork)"
        }
        .joined(separator: "|")
    }

    private func shouldRebuildHomeSongsForRealDiscovery() -> Bool {
        let frontSongs = Array(homeSongs.prefix(48))
        guard frontSongs.isEmpty == false else { return false }
        guard songs.contains(where: { $0.source.isRealDiscoverySource }) else { return false }

        let demoFrontCount = frontSongs.filter { $0.source == .demo }.count
        let realFrontCount = frontSongs.filter { $0.source.isRealDiscoverySource }.count
        return demoFrontCount >= max(8, frontSongs.count / 2) && realFrontCount < 12
    }

    private func rebuildHomeSongsForRealDiscovery() {
        homeSessionSalt = Double.random(in: 0..<10_000)
        homeSourceSignature = homeSourceSignature(for: songs)
        homeSongs = initialHomeSongs()
        homePendingSongs = homeSongs
        homeFlipVariations = makeHomeFlipVariations(count: homeSongs.count)
        homeFlippingIndices = Set(homeSongs.indices)
        resetHomeFlipState()
        rememberRecentlyShownHomeSongs(homeSongs)
        PlayerArtworkWarmupCache.shared.preload(songs: Array(homeSongs.prefix(120)))
    }

    private func refreshVisibleHomeSongMetadata() {
        guard homeSongs.isEmpty == false else { return }
        var latestByID: [Int: DemoSong] = [:]
        songs.forEach { latestByID[$0.id] = $0 }

        let refreshedSongs = homeSongs.map { song in
            guard let latestSong = latestByID[song.id] else { return song }
            return mergedHomeSong(current: song, latest: latestSong)
        }
        let refreshedPendingSongs = homePendingSongs.map { song in
            guard let latestSong = latestByID[song.id] else { return song }
            return mergedHomeSong(current: song, latest: latestSong)
        }

        guard refreshedSongs.map(\.id) == homeSongs.map(\.id) else { return }
        homeSongs = refreshedSongs
        homePendingSongs = refreshedPendingSongs
        PlayerArtworkWarmupCache.shared.preload(songs: Array((refreshedSongs + refreshedPendingSongs).prefix(120)))
    }

    private func mergedHomeSong(current: DemoSong, latest: DemoSong) -> DemoSong {
        let artworkImage = latest.artworkImage ?? current.artworkImage
        let backdropImage = latest.backdropImage ?? current.backdropImage ?? artworkImage?.playerBackdropImage
        return DemoSong(
            id: latest.id,
            title: latest.title,
            artist: latest.artist,
            colors: latest.artworkImage == nil ? current.colors : latest.colors,
            mediaItem: latest.mediaItem ?? current.mediaItem,
            storeID: latest.storeID ?? current.storeID,
            previewURL: latest.previewURL ?? current.previewURL,
            spotifyURI: latest.spotifyURI ?? current.spotifyURI,
            artworkImage: artworkImage,
            backdropImage: backdropImage,
            lyricsText: latest.lyricsText ?? current.lyricsText,
            magicColor: latest.artworkImage == nil ? current.magicColor : latest.magicColor,
            source: latest.source
        )
    }

    private func dislikeHomeSong(_ song: DemoSong) {
        guard song.isPlaceholder == false else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.54)
        var dislikedKeys = homeDislikedSongKeysSet()
        dislikedKeys.insert(homeDislikeKey(for: song))
        homeDislikedSongKeysRaw = dislikedKeys.sorted().joined(separator: "\n")
        rememberTemporarilySkippedHomeSongs([song.id])

        resetHomeFlipState()

        var nextSongs = visibleHomeSongs
        let dislikedKey = homeDislikeKey(for: song)
        guard let targetIndex = nextSongs.firstIndex(where: { candidate in
            candidate.id == song.id || homeDislikeKey(for: candidate) == dislikedKey
        }) else {
            syncHomeSongsIfNeeded()
            return
        }

        if let replacement = replacementHomeSong(avoiding: nextSongs.map(\.id)) {
            nextSongs[targetIndex] = replacement
            rememberRecentlyShownHomeSongs([replacement])
            PlayerArtworkWarmupCache.shared.preload(songs: [replacement])
        } else {
            nextSongs.remove(at: targetIndex)
        }

        let filteredSongs = nextSongs.filter { isHomeSongDisliked($0) == false }
        withAnimation(.smooth(duration: 0.18, extraBounce: 0.0)) {
            homeSongs = filteredSongs
            homePendingSongs = []
        }
        homeSourceSignature = homeSourceSignature(for: songs)
    }

    private func replacementHomeSong(avoiding existingIDs: [Int]) -> DemoSong? {
        let existingIDSet = Set(existingIDs)
        let existingKeys = Set(visibleHomeSongs.map(homeDislikeKey(for:)))
        let candidates = songs.filter { candidate in
            candidate.isPlaceholder == false &&
            existingIDSet.contains(candidate.id) == false &&
            existingKeys.contains(homeDislikeKey(for: candidate)) == false &&
            isHomeSongDisliked(candidate) == false
        }
        guard candidates.isEmpty == false else { return nil }

        return diversifiedHomeSongs(
            from: candidates,
            overflow: candidates,
            limit: min(max(24, candidates.count), 96)
        )
        .first
    }

    private func appendNewHomeSongsFromSource() {
        guard homeSongs.isEmpty == false, isHomeFlipping == false else { return }
        var seenIDs = Set(homeSongs.map(\.id))
        let additions = songs.filter { song in
            guard seenIDs.contains(song.id) == false else { return false }
            seenIDs.insert(song.id)
            return true
        }
        appendHomeSongsWithFlip(additions)
    }

    private func loadMoreHomeSongsIfNeeded(_ slot: HomeSongSlot) {
        guard activeTab != .settings else { return }
        guard isHomeLoadingMore == false else { return }
        if visibleHomeSongs.count < 24 {
            ensureHomeHasEnoughSongsIfNeeded()
            return
        }
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

    private func ensureHomeHasEnoughSongsIfNeeded(targetCount: Int = 96) {
        guard activeTab != .settings else { return }
        guard isHomeLoadingMore == false else { return }
        guard visibleHomeSongs.filter({ $0.isHomeSurfacePlayable && $0.isPlaceholder == false }).count < targetCount else { return }

        var seenIDs = Set(visibleHomeSongs.map(\.id))
        let sourceAdditions = songs.filter { song in
            guard song.isHomeSurfacePlayable, song.isPlaceholder == false else { return false }
            guard seenIDs.contains(song.id) == false else { return false }
            seenIDs.insert(song.id)
            return true
        }
        if sourceAdditions.isEmpty == false {
            _ = appendHomeSongsWithFlip(sourceAdditions)
            return
        }

        guard visibleHomeSongs.filter({ $0.isHomeSurfacePlayable && $0.isPlaceholder == false }).count < targetCount else { return }
        homeAutoFillTask?.cancel()
        isHomeLoadingMore = true
        isHomeAppendingMore = false
        let startPage = homeLoadMorePage
        homeLoadMorePage += 1

        homeAutoFillTask = Task { @MainActor in
            var page = startPage
            var attempts = 0
            while !Task.isCancelled,
                  activeTab != .settings,
                  visibleHomeSongs.filter({ $0.isHomeSurfacePlayable && $0.isPlaceholder == false }).count < targetCount,
                  attempts < 4 {
                let additions = await musicConnector.loadMoreDiscoverySongs(page: page)
                guard !Task.isCancelled else { return }
                let appendedCount = appendHomeSongsWithFlip(additions)
                attempts += 1
                page += 1
                homeLoadMorePage = max(homeLoadMorePage, page)
                if appendedCount > 0 {
                    return
                }
                if appendedCount == 0 {
                    try? await Task.sleep(for: .milliseconds(240))
                }
            }
            isHomeLoadingMore = false
            isHomeAppendingMore = false
        }
    }

    private func appendLoadedHomeSongs(_ additions: [DemoSong]) {
        let appendedCount = appendHomeSongsWithFlip(additions)
        guard appendedCount > 0 else {
            isHomeLoadingMore = false
            isHomeAppendingMore = false
            return
        }
    }

    @discardableResult
    private func appendHomeSongsWithFlip(_ additions: [DemoSong]) -> Int {
        guard additions.isEmpty == false else { return 0 }
        let currentHasOnlyLoadingCards = homeSongs.contains {
            $0.isPlaceholder || $0.source == .demo || $0.isHomeSurfacePlayable == false
        }
        let current = (homeSongs.isEmpty || currentHasOnlyLoadingCards) ? songs : homeSongs
        var seenIDs = Set(current.map(\.id))
        let uniqueAdditions = additions.filter { song in
            guard song.isHomeSurfacePlayable else { return false }
            guard seenIDs.contains(song.id) == false else { return false }
            seenIDs.insert(song.id)
            return true
        }
        guard uniqueAdditions.isEmpty == false else { return 0 }

        let orderedAdditions = diversifiedHomeSongs(
            from: uniqueAdditions,
            overflow: uniqueAdditions,
            limit: uniqueAdditions.count
        )
        let baseSongs = currentHasOnlyLoadingCards ? [] : current
        let targetSongs = baseSongs + orderedAdditions
        let newCardStart = baseSongs.count
        let flippingIndices = Set(newCardStart..<targetSongs.count)

        homeFlipTask?.cancel()
        homeSongs = targetSongs
        homePendingSongs = targetSongs
        homeFlipVariations = makeHomeFlipVariations(count: targetSongs.count)
        homeFlippingIndices = flippingIndices
        homeAppearingFlipIndices = flippingIndices
        homeFlipGeneration = UUID()
        isHomeFlipping = true
        isHomeAppendingMore = true
        rememberRecentlyShownHomeSongs(orderedAdditions)
        PlayerArtworkWarmupCache.shared.preload(songs: Array(orderedAdditions.prefix(80)))

        let generation = homeFlipGeneration
        homeFlipTask = Task { @MainActor in
            let rows = max(1, Int(ceil(Double(orderedAdditions.count) / 4.0)))
            try? await Task.sleep(for: .milliseconds(rows * 70 + 940))
            guard !Task.isCancelled, homeFlipGeneration == generation else { return }
            homeSongs = targetSongs
            homePendingSongs = []
            homeFlipVariations = [:]
            homeFlippingIndices = []
            homeAppearingFlipIndices = []
            isHomeFlipping = false
            isHomeLoadingMore = false
            isHomeAppendingMore = false
        }

        return orderedAdditions.count
    }

    @discardableResult
    private func appendHomeSongsWithoutFlip(_ additions: [DemoSong]) -> Int {
        guard additions.isEmpty == false else { return 0 }
        let currentHasOnlyLoadingCards = homeSongs.contains {
            $0.isPlaceholder || $0.source == .demo || $0.isHomeSurfacePlayable == false
        }
        let current = (homeSongs.isEmpty || currentHasOnlyLoadingCards) ? songs : homeSongs
        var seenIDs = Set(current.map(\.id))
        let uniqueAdditions = additions.filter { song in
            guard song.isHomeSurfacePlayable else { return false }
            guard seenIDs.contains(song.id) == false else { return false }
            seenIDs.insert(song.id)
            return true
        }
        guard uniqueAdditions.isEmpty == false else { return 0 }

        let orderedAdditions = diversifiedHomeSongs(
            from: uniqueAdditions,
            overflow: uniqueAdditions,
            limit: uniqueAdditions.count
        )
        let targetSongs = currentHasOnlyLoadingCards ? orderedAdditions : current + orderedAdditions
        homeSongs = targetSongs
        homePendingSongs = targetSongs
        homeFlipVariations = makeHomeFlipVariations(count: targetSongs.count)
        homeAppearingFlipIndices = []
        isHomeFlipping = false
        rememberRecentlyShownHomeSongs(orderedAdditions)
        PlayerArtworkWarmupCache.shared.preload(songs: Array(orderedAdditions.prefix(80)))
        return orderedAdditions.count
    }

    private func reshuffleHomeSongsWithFlip() {
        guard isHomeSurfaceVisible, songs.count > 1 else { return }
        registerHomeInteraction(resetDrift: false)
        resetHomeFlipState()
        rememberTemporarilySkippedHomeSongs(visibleHomeSongs.prefix(48).map(\.id))

        let nextSongs = reshuffledHomeSongs()
        startHomeFlip(to: nextSongs, hapticStyle: .medium)
    }

    private func startHomeFlip(to nextSongs: [DemoSong], hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard nextSongs.isEmpty == false else { return }
        resetHomeFlipState()
        homePendingSongs = nextSongs
        homeFlipVariations = makeHomeFlipVariations(count: nextSongs.count)
        let generation = UUID()
        homeFlipGeneration = generation
        homeFlippingIndices = Set(nextSongs.indices)
        homeAppearingFlipIndices = []
        isHomeFlipping = true
        PlayerArtworkWarmupCache.shared.preload(songs: Array(nextSongs.prefix(120)))

        homeFlipTask = Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: hapticStyle)
            generator.prepare()

            let timeline = nextSongs.indices.map { index -> (index: Int, startMs: Int, duration: Double) in
                let variation = homeFlipVariations[index] ?? .zero
                let startMs = max(0, Int((variation.delay * 1000).rounded()))
                let duration = Double(variation.durationScale) * 0.48
                return (index, startMs, duration)
            }

            var lastStart = 0
            for item in timeline.sorted(by: { $0.startMs < $1.startMs }) {
                try? await Task.sleep(for: .milliseconds(max(0, item.startMs - lastStart)))
                lastStart = item.startMs
                guard !Task.isCancelled, isHomeFlipping, homeFlipGeneration == generation else { return }
                generator.impactOccurred(intensity: 0.52)
            }

            let finalDelay = (timeline.map { $0.startMs }.max() ?? 0) + 760
            try? await Task.sleep(for: .milliseconds(max(0, finalDelay - lastStart)))
            guard !Task.isCancelled, homeFlipGeneration == generation else { return }
            homeSongs = nextSongs
            rememberRecentlyShownHomeSongs(nextSongs)
            resetHomeFlipState()
        }
    }

    private func resetHomeFlipState() {
        homeFlipTask?.cancel()
        homeFlipTask = nil
        homeFlipGeneration = UUID()
        homePendingSongs = []
        homeFlipVariations = [:]
        homeFlippingIndices = []
        homeAppearingFlipIndices = []
        isHomeFlipping = false
    }

    private func makeHomeFlipVariations(count: Int) -> [Int: HomeFlipVariation] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { index in
            let row = index / 4
            let column = index % 4
            let rowBase = row * 72
            let columnScatter = [34, 5, 52, 19][column]
            let randomScatter = Int.random(in: -8...86)
            return (
                index,
                HomeFlipVariation(
                    delay: CGFloat(max(0, rowBase + columnScatter + randomScatter)) / 1000,
                    durationScale: CGFloat.random(in: 0.92...1.20),
                    tilt: Double.random(in: -3.6...3.6),
                    lift: CGFloat.random(in: -2.5...3.5)
                )
            )
        })
    }

    private func initialHomeSongs() -> [DemoSong] {
        timeMatchedHomeSongs(
            from: songs,
            avoiding: temporarilySkippedHomeSongIDsSet(),
            excludingCurrentFront: false,
            limit: 96
        )
    }

    private func reshuffledHomeSongs() -> [DemoSong] {
        homeSessionSalt = Double.random(in: 0..<10_000)
        return timeMatchedHomeSongs(
            from: songs,
            avoiding: temporarilySkippedHomeSongIDsSet(),
            excludingCurrentFront: true,
            limit: max(96, min(songs.count, visibleHomeSongs.count))
        )
    }

    private func timeMatchedHomeSongs(
        from source: [DemoSong],
        avoiding rejectedIDs: Set<Int>,
        excludingCurrentFront: Bool,
        limit: Int
    ) -> [DemoSong] {
        let currentFrontIDs = Set(visibleHomeSongs.prefix(64).map(\.id))
        let recentlyShownIDs = recentlyShownHomeSongIDsSet()
        let cleanSource = uniqueHomeSongs(from: source).filter {
            $0.isPlaceholder == false && isHomeSongDisliked($0) == false
        }
        let preferred = cleanSource.filter { song in
            rejectedIDs.contains(song.id) == false &&
            recentlyShownIDs.contains(song.id) == false &&
            recentlyShownHomeSongKeysSet().contains(homeDislikeKey(for: song)) == false &&
            (!excludingCurrentFront || currentFrontIDs.contains(song.id) == false)
        }
        let fallback = cleanSource.filter { song in
            !excludingCurrentFront || currentFrontIDs.contains(song.id) == false
        }
        let pool = preferred.isEmpty ? (fallback.isEmpty ? cleanSource : fallback) : preferred
        let result = spotifySpotlightedHomeSongs(
            diversifiedHomeSongs(from: pool, overflow: cleanSource, limit: limit),
            source: cleanSource,
            limit: limit
        )
        guard result.first?.id == visibleHomeSongs.first?.id, result.count > 1 else { return result }
        return Array(result.dropFirst()) + [result[0]]
    }

    private func spotifySpotlightedHomeSongs(_ orderedSongs: [DemoSong], source: [DemoSong], limit: Int) -> [DemoSong] {
        let spotifySongs = uniqueHomeSongs(from: orderedSongs + source)
            .filter { $0.source == .spotify }
        guard spotifySongs.isEmpty == false else { return orderedSongs }

        let spotifyFront = Array(spotifySongs.prefix(12))
        let otherSongs = orderedSongs.filter { $0.source != .spotify }
        let spotifySlots = Set([0, 3, 6, 10, 14, 18, 22, 26, 30, 34, 38, 42])
        var result: [DemoSong] = []
        var spotifyIndex = 0
        var otherIndex = 0

        while result.count < limit, (spotifyIndex < spotifyFront.count || otherIndex < otherSongs.count) {
            if spotifySlots.contains(result.count), spotifyIndex < spotifyFront.count {
                result.append(spotifyFront[spotifyIndex])
                spotifyIndex += 1
            } else if otherIndex < otherSongs.count {
                result.append(otherSongs[otherIndex])
                otherIndex += 1
            } else if spotifyIndex < spotifyFront.count {
                result.append(spotifyFront[spotifyIndex])
                spotifyIndex += 1
            }
        }

        return Array(uniqueHomeSongs(from: result + orderedSongs).prefix(limit))
    }

    private func diversifiedHomeSongs(from pool: [DemoSong], overflow: [DemoSong], limit: Int) -> [DemoSong] {
        let mood = HomeTimeMood.current
        let cappedLimit = max(24, min(limit, max(pool.count, overflow.count)))
        let scoredPool = pool.map { song in
            (song: song, score: homeRecommendationScore(for: song, mood: mood, recentPenalty: homeExposurePenalty(for: song)))
        }

        let timeLayer = weightedHomeSample(
            from: scoredPool,
            limit: cappedLimit,
            temperature: 0.68
        )
        let discoveryLayer = weightedHomeSample(
            from: scoredPool.map { item in
                let boost = item.song.source == .recommendation ? 1.25 : (item.song.source == .spotify ? 0.75 : 0)
                return (song: item.song, score: item.score + boost + Double.random(in: 0...0.9))
            },
            limit: cappedLimit,
            temperature: 0.95
        )
        let explorationLayer = weightedHomeSample(
            from: overflow.map { song in
                let recentPenalty = (pool.contains(where: { $0.id == song.id }) ? 0 : -0.35) + homeExposurePenalty(for: song) * 0.7
                return (song: song, score: homeRecommendationScore(for: song, mood: mood, recentPenalty: recentPenalty) + Double.random(in: 0...1.9))
            },
            limit: cappedLimit,
            temperature: 1.35
        )

        let sourceBalanced = sourceBalancedHomeSongs(
            from: [timeLayer, discoveryLayer, explorationLayer],
            overflow: overflow,
            limit: cappedLimit
        )
        guard sourceBalanced.isEmpty == false else { return [] }
        return sourceBalanced
    }

    private func sourceBalancedHomeSongs(from layers: [[DemoSong]], overflow: [DemoSong], limit: Int) -> [DemoSong] {
        let candidates = uniqueHomeSongs(from: layers.flatMap { $0 } + overflow)
        guard candidates.isEmpty == false else { return [] }

        let cappedLimit = max(1, limit)
        var buckets = Dictionary(grouping: candidates, by: \.source)
        let pattern = homeSourcePattern(availableSources: Set(buckets.keys))
        var seenIDs = Set<Int>()
        var artistCounts: [String: Int] = [:]
        var result: [DemoSong] = []
        var lastSource: DemoSongSource?
        var sourceRun = 0

        func hasOtherAvailableSource(excluding source: DemoSongSource) -> Bool {
            buckets.contains { entry in
                entry.key != source && entry.value.contains { seenIDs.contains($0.id) == false }
            }
        }

        func takeSong(from source: DemoSongSource, relaxArtistLimit: Bool) -> DemoSong? {
            guard var bucket = buckets[source], bucket.isEmpty == false else { return nil }
            let artistLimit = result.count < 36 ? 2 : 4
            for index in bucket.indices {
                let song = bucket[index]
                guard seenIDs.contains(song.id) == false else { continue }
                let artist = normalizedHomeArtist(song.artist)
                if relaxArtistLimit == false, (artistCounts[artist] ?? 0) >= artistLimit {
                    continue
                }
                if relaxArtistLimit == false,
                   sourceRun >= 2,
                   lastSource == source,
                   hasOtherAvailableSource(excluding: source) {
                    continue
                }
                bucket.remove(at: index)
                buckets[source] = bucket
                return song
            }
            buckets[source] = bucket
            return nil
        }

        func append(_ song: DemoSong) {
            seenIDs.insert(song.id)
            let artist = normalizedHomeArtist(song.artist)
            artistCounts[artist, default: 0] += 1
            if lastSource == song.source {
                sourceRun += 1
            } else {
                lastSource = song.source
                sourceRun = 1
            }
            result.append(song)
        }

        while result.count < cappedLimit {
            let before = result.count
            for source in pattern {
                if let song = takeSong(from: source, relaxArtistLimit: false) {
                    append(song)
                }
                if result.count >= cappedLimit { break }
            }
            if result.count == before { break }
        }

        if result.count < cappedLimit {
            for source in pattern {
                while result.count < cappedLimit, let song = takeSong(from: source, relaxArtistLimit: true) {
                    append(song)
                }
            }
        }

        return result
    }

    private func homeSourcePattern(availableSources: Set<DemoSongSource>) -> [DemoSongSource] {
        let preferred: [DemoSongSource] = [
            .spotify,
            .recommendation,
            .library,
            .recommendation,
            .spotify,
            .library,
            .recommendation
        ]
        let filtered = preferred.filter { availableSources.contains($0) }
        let extras = availableSources
            .filter { filtered.contains($0) == false }
            .sorted { $0.rotationPriority < $1.rotationPriority }
        return filtered.isEmpty ? Array(extras) : filtered + extras
    }

    private func homeExposurePenalty(for song: DemoSong) -> Double {
        guard let index = Array(recentlyShownHomeSongIDs.reversed()).firstIndex(of: song.id) else {
            return recentlyShownHomeSongKeysSet().contains(homeDislikeKey(for: song)) ? -1.85 : 0
        }
        let recency = Double(index)
        return -max(0.65, 3.4 - recency * 0.03)
    }

    private func homeRecommendationScore(for song: DemoSong, mood: HomeTimeMood, recentPenalty: Double) -> Double {
        let sourceBoost: Double
        switch song.source {
        case .recommendation: sourceBoost = 1.25
        case .spotify: sourceBoost = 0.95
        case .library: sourceBoost = 0.72
        case .demo: sourceBoost = -0.85
        case .placeholder: sourceBoost = -2.0
        }
        return mood.score(song) * 1.55
            + sourceBoost
            + deterministicHomeJitter(for: song) * 1.05
            + Double.random(in: 0...0.85)
            + recentPenalty
    }

    private func weightedHomeSample(
        from scoredSongs: [(song: DemoSong, score: Double)],
        limit: Int,
        temperature: Double
    ) -> [DemoSong] {
        var remaining = scoredSongs
        var result: [DemoSong] = []

        while remaining.isEmpty == false, result.count < limit {
            let bestScore = remaining.map(\.score).max() ?? 0
            let weights = remaining.map { item in
                max(0.08, exp((item.score - bestScore) / max(temperature, 0.1)))
            }
            let totalWeight = weights.reduce(0, +)
            var pick = Double.random(in: 0..<max(totalWeight, 0.001))
            var selectedIndex = remaining.startIndex

            for index in remaining.indices {
                pick -= weights[index]
                if pick <= 0 {
                    selectedIndex = index
                    break
                }
            }

            result.append(remaining.remove(at: selectedIndex).song)
        }

        return result
    }

    private func deterministicHomeJitter(for song: DemoSong) -> Double {
        let key = "\(song.id)-\(song.title)-\(song.artist)"
        let keyValue = key.unicodeScalars.reduce(Double(song.id + 31)) { partial, scalar in
            partial + Double(scalar.value) * 0.019
        }
        let value = sin(keyValue * 12.9898 + homeSessionSalt * 78.233) * 43_758.5453
        return value - floor(value)
    }

    private func uniqueHomeSongs(from songs: [DemoSong]) -> [DemoSong] {
        var seenKeys = Set<String>()
        return songs.compactMap { song in
            let key = "\(song.title.lowercased())|\(song.artist.lowercased())|\(song.storeID ?? "")|\(song.mediaItem?.persistentID ?? 0)"
            guard seenKeys.insert(key).inserted else { return nil }
            return song
        }
    }

    private func normalizedHomeArtist(_ artist: String) -> String {
        artist
            .lowercased()
            .replacingOccurrences(of: #"(\s+feat\.?.*|\s+ft\.?.*)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func temporarilySkippedHomeSongIDsSet() -> Set<Int> {
        Set(temporarilySkippedHomeSongIDs)
    }

    private func recentlyShownHomeSongIDsSet() -> Set<Int> {
        Set(recentlyShownHomeSongIDs)
    }

    private func recentlyShownHomeSongKeysSet() -> Set<String> {
        Set(
            homeRecentlyShownSongKeysRaw
                .split(whereSeparator: \.isNewline)
                .map(String.init)
        )
    }

    private func homeDislikedSongKeysSet() -> Set<String> {
        Set(
            homeDislikedSongKeysRaw
                .split(whereSeparator: \.isNewline)
                .map(String.init)
        )
    }

    private func isHomeSongDisliked(_ song: DemoSong) -> Bool {
        homeDislikedSongKeysSet().contains(homeDislikeKey(for: song))
    }

    private func homeDislikeKey(for song: DemoSong) -> String {
        "\(normalizedHomeFeedbackText(song.title))|\(normalizedHomeFeedbackText(song.artist))"
    }

    private func normalizedHomeFeedbackText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(
                of: #"[\(\[][^\)\]]*(remix|mixed|mix|edit|version|live|remaster|sped up|slowed|instrumental)[^\)\]]*[\)\]]"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"[^a-z0-9\u{4e00}-\u{9fff}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func rememberRecentlyShownHomeSongs(_ songs: [DemoSong]) {
        let realIDs = songs
            .prefix(72)
            .filter { $0.id > 0 && $0.isPlaceholder == false }
            .map(\.id)
        guard realIDs.isEmpty == false else { return }
        var stored = recentlyShownHomeSongIDs
        stored.append(contentsOf: realIDs)
        var seen = Set<Int>()
        let capped = stored.reversed().filter { seen.insert($0).inserted }.prefix(220).reversed()
        recentlyShownHomeSongIDs = Array(capped)

        let realKeys = songs
            .prefix(96)
            .filter { $0.id > 0 && $0.isPlaceholder == false }
            .map(homeDislikeKey(for:))
        var keyStore = homeRecentlyShownSongKeysRaw
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        keyStore.append(contentsOf: realKeys)
        var seenKeys = Set<String>()
        let cappedKeys = keyStore.reversed().filter { seenKeys.insert($0).inserted }.prefix(520).reversed()
        homeRecentlyShownSongKeysRaw = Array(cappedKeys).joined(separator: "\n")
    }

    private func registerHomeInteraction(resetDrift: Bool = true) {
        guard isHomeSurfaceVisible else { return }
        scheduleHomeIdleDrift(resetDrift: resetDrift)
    }

    private func scheduleHomeIdleDrift(resetDrift: Bool = true) {
        homeIdleTask?.cancel()
        if resetDrift, homeDriftAmount != 0 {
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
        case 0, 2:
            return -18
        default:
            return 0
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

private struct HomeCoverGravity {
    let offset: CGSize
    let scale: CGFloat
    let glow: CGFloat

    static let zero = HomeCoverGravity(offset: .zero, scale: 1, glow: 0)
}

private struct MusicMoodPreference: Equatable {
    var energy: Double
    var warmth: Double

    static let neutral = MusicMoodPreference(energy: 0, warmth: 0)

    static func load() -> MusicMoodPreference {
        MusicMoodPreference(
            energy: UserDefaults.standard.object(forKey: "moodPaletteEnergy") as? Double ?? 0,
            warmth: UserDefaults.standard.object(forKey: "moodPaletteWarmth") as? Double ?? 0
        )
    }

    func save() {
        UserDefaults.standard.set(energy, forKey: "moodPaletteEnergy")
        UserDefaults.standard.set(warmth, forKey: "moodPaletteWarmth")
    }

    var label: String {
        switch (energy, warmth) {
        case let (e, w) where e > 0.38 && w > 0.18: return "热烈明亮"
        case let (e, w) where e > 0.30 && w <= 0.18: return "清醒律动"
        case let (e, w) where e < -0.30 && w < -0.12: return "冷静深夜"
        case let (e, w) where e < -0.28 && w >= -0.12: return "柔软慢听"
        case let (_, w) where w > 0.42: return "暖色流行"
        case let (_, w) where w < -0.42: return "蓝调氛围"
        default: return "自然流动"
        }
    }

    var tint: Color {
        let red = min(1, max(0, 0.52 + warmth * 0.28 + max(energy, 0) * 0.16))
        let green = min(1, max(0, 0.64 + energy * 0.12))
        let blue = min(1, max(0, 0.82 - warmth * 0.28 - min(energy, 0) * 0.10))
        return Color(
            red: red,
            green: green,
            blue: blue
        )
    }

    var queryHints: [String] {
        var hints: [String] = []
        if energy > 0.34 {
            hints += ["upbeat discoveries", "dance pop energy", "fresh tempo songs"]
        } else if energy < -0.34 {
            hints += ["slow listening songs", "soft ambient pop", "quiet night music"]
        }
        if warmth > 0.34 {
            hints += ["warm pop songs", "sunny soul music", "feel good classics"]
        } else if warmth < -0.34 {
            hints += ["blue night songs", "dream pop discoveries", "cinematic electronic"]
        }
        return hints
    }

    func score(_ song: DemoSong) -> Double {
        score(title: song.title, artist: song.artist, rhythmEnergy: song.rhythmEnergy)
    }

    func score(title: String, artist: String, rhythmEnergy: Double) -> Double {
        let energyFit = 1 - abs(rhythmEnergy - (0.48 + energy * 0.34))
        let text = "\(title) \(artist)".lowercased()
        let warmMatch = ["sun", "gold", "sweet", "hot", "love", "summer"].contains { text.contains($0) } ? 0.22 : 0
        let coolMatch = ["blue", "night", "moon", "dark", "dream", "ocean"].contains { text.contains($0) } ? 0.22 : 0
        return energyFit + (warmth >= 0 ? warmMatch : coolMatch)
    }
}

private enum HomeTimeMood: Equatable {
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

    var recommendationLabel: String {
        switch self {
        case .morning: return "早晨"
        case .afternoon: return "下午"
        case .evening: return "夜晚"
        case .lateNight: return "深夜"
        }
    }

    func score(_ song: DemoSong) -> Double {
        let text = "\(song.title) \(song.artist)".lowercased()
        let colorScore = song.colors.reduce(0.0) { partial, color in
            partial + colorMoodScore(color)
        } / Double(max(song.colors.count, 1))
        let keywordScore = keywordMoodScore(text)
        let rhythmScore = 1 - abs(song.rhythmEnergy - preferredRhythmEnergy)
        return colorScore + keywordScore + rhythmScore * 0.82
    }

    private var preferredRhythmEnergy: Double {
        switch self {
        case .morning: return 0.46
        case .afternoon: return 0.78
        case .evening: return 0.54
        case .lateNight: return 0.34
        }
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
    let mood: HomeTimeMood

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

private struct SpotifyHomeSignal: View {
    let songCount: Int

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.1, green: 0.86, blue: 0.36))
                    .frame(width: 24, height: 24)
                    .shadow(color: Color(red: 0.1, green: 0.86, blue: 0.36).opacity(0.52), radius: 10, y: 3)

                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.black.opacity(0.82))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Spotify 已混入首页")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(songCount) 首来自 Spotify")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 11)
        .frame(height: 40)
        .background(.black.opacity(0.34), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(red: 0.1, green: 0.86, blue: 0.36).opacity(0.72), lineWidth: 1)
        }
    }
}

private struct TimeMoodCapsule: View {
    let mood: HomeTimeMood
    let preference: MusicMoodPreference

    private var timeText: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(preference.tint)
                .frame(width: 7, height: 7)
                .shadow(color: preference.tint.opacity(0.72), radius: 7)

            Text("\(timeText) · \(mood.recommendationLabel) · \(preference.label)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(.black.opacity(0.26))
        .clipShape(Capsule())
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

private struct InitialLibraryLoadingOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            Color.black.opacity(0.40)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .controlSize(.large)

                VStack(spacing: 10) {
                    VStack(spacing: 5) {
                        Text("正在加载曲库")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.white)

                        Text("正在准备可播放歌曲")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
            }
            .padding(.horizontal, 32)
        }
        .allowsHitTesting(true)
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
                    MusicConnectionControl(
                        connectTitle: "连接 Spotify",
                        connectedTitle: "Spotify 已连接",
                        disconnectTitle: "登出 Spotify",
                        subtitle: connector.spotifyStatusText,
                        systemName: "music.note",
                        tint: Color(red: 0.1, green: 0.84, blue: 0.36),
                        isLoading: connector.isConnectingSpotify,
                        isConnected: connector.isSpotifyReady,
                        onConnect: {
                            Task { await connector.connectSpotify() }
                        },
                        onDisconnect: {
                            connector.disconnectSpotify()
                        }
                    )

                    MusicConnectionControl(
                        connectTitle: "连接 Apple Music",
                        connectedTitle: "Apple Music 已连接",
                        disconnectTitle: "登出 Apple Music",
                        subtitle: connector.appleMusicStatusText,
                        systemName: "music.note.list",
                        tint: Color(red: 1.0, green: 0.18, blue: 0.35),
                        isLoading: connector.isConnectingAppleMusic,
                        isConnected: connector.isAppleMusicReady,
                        onConnect: {
                            Task {
                                await connector.connectAppleMusic()
                                if connector.isAppleMusicReady {
                                    withAnimation(.smooth(duration: 0.22, extraBounce: 0.0)) {
                                        activeTab = .home
                                    }
                                }
                            }
                        },
                        onDisconnect: {
                            connector.disconnectAppleMusic()
                        }
                    )

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
                    MusicConnectionControl(
                        connectTitle: "连接 Spotify",
                        connectedTitle: "Spotify 已连接",
                        disconnectTitle: "登出 Spotify",
                        subtitle: connector.spotifyStatusText,
                        systemName: "music.note",
                        tint: Color(red: 0.1, green: 0.84, blue: 0.36),
                        isLoading: connector.isConnectingSpotify,
                        isConnected: connector.isSpotifyReady,
                        onConnect: {
                            Task { await connector.connectSpotify() }
                        },
                        onDisconnect: {
                            connector.disconnectSpotify()
                        }
                    )

                    MusicConnectionControl(
                        connectTitle: "连接 Apple Music",
                        connectedTitle: "Apple Music 已连接",
                        disconnectTitle: "登出 Apple Music",
                        subtitle: connector.appleMusicStatusText,
                        systemName: "music.note.list",
                        tint: Color(red: 1.0, green: 0.18, blue: 0.35),
                        isLoading: connector.isConnectingAppleMusic,
                        isConnected: connector.isAppleMusicReady,
                        onConnect: {
                            Task {
                                await connector.connectAppleMusic()
                                if connector.isAppleMusicReady {
                                    onClose()
                                }
                            }
                        },
                        onDisconnect: {
                            connector.disconnectAppleMusic()
                        }
                    )

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

private struct MusicConnectionControl: View {
    let connectTitle: String
    let connectedTitle: String
    let disconnectTitle: String
    let subtitle: String
    let systemName: String
    let tint: Color
    let isLoading: Bool
    let isConnected: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            MusicConnectButton(
                title: isConnected ? connectedTitle : connectTitle,
                subtitle: subtitle,
                systemName: isConnected ? "checkmark.circle.fill" : systemName,
                tint: tint,
                isLoading: isLoading,
                action: onConnect
            )

            if isConnected {
                Button(role: .destructive, action: onDisconnect) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 13, weight: .bold))

                        Text(disconnectTitle)
                            .font(.system(size: 13, weight: .black))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.30, blue: 0.36))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color(red: 1.0, green: 0.12, blue: 0.20).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(red: 1.0, green: 0.22, blue: 0.30).opacity(0.26), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.20, extraBounce: 0.0), value: isConnected)
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
    @Published var homeFeedSongs: [DemoSong] = []
    @Published private(set) var isInitialLibraryLoading = true
    @Published private(set) var isHomeFeedRefreshing = false
    @Published private(set) var isSpotifyLibraryRefreshing = false
    @Published var recommendedSongs: [DemoSong] = []
    @Published var discoveryExtraSongs: [DemoSong] = []
    @Published var message: String?
    @Published var currentSong: DemoSong?
    @Published var playingSongID: Int?
    @Published var isPlaying = false
    @Published var isPlaybackTransitioning = false
    @Published var showPlaybackLoadingToast = false
    @Published var moodPreference = MusicMoodPreference.load()
    @Published private var fetchedLyricsByKey: [String: String] = [:]
    @Published private var loadingLyricKeys: Set<String> = []

    @AppStorage("appleMusicConnected") private var appleMusicConnected = false
    @AppStorage("spotifyAccessToken") private var spotifyAccessToken = ""
    @AppStorage("spotifyRefreshToken") private var spotifyRefreshToken = ""
    @AppStorage("spotifyTokenExpiresAt") private var spotifyTokenExpiresAt = 0.0
    @AppStorage("selectedApplePlaylistID") var selectedApplePlaylistID = MusicPlaylistOption.allID
    @AppStorage("selectedSpotifyPlaylistID") var selectedSpotifyPlaylistID = MusicPlaylistOption.allID
    @AppStorage("aiRecommendationsEnabled") var aiRecommendationsEnabled = true
    @AppStorage("spotifyPrivacyResetVersion") private var spotifyPrivacyResetVersion = 0

    private let spotifyAuthenticator = SpotifyPKCEAuthenticator()
    private let requiredSpotifyPrivacyResetVersion = 1
    private var playbackLoadingTask: Task<Void, Never>?
    private var queuedPlaybackTask: Task<Void, Never>?
    private var playbackPrefetchTask: Task<Void, Never>?
    private var homeFeedTask: Task<Void, Never>?
    private var delayedHomeFeedRefreshTask: Task<Void, Never>?
    private var spotifyStartupRefreshTask: Task<Void, Never>?
    private var spotifyFullRefreshTask: Task<Void, Never>?
    private var initialLoadingFinishTask: Task<Void, Never>?
    private var initialLoadingTimeoutTask: Task<Void, Never>?
    private var initialLibraryLoadingStartedAt = Date()
    private var homeFeedRequestID = 0
    private var recommendationTask: Task<Void, Never>?
    private var playbackObservers: [NSObjectProtocol] = []
    private var previewAudioPlayer: AVPlayer?
    private var previewEndObserver: NSObjectProtocol?
    private var previewPlaybackTask: Task<Void, Never>?
    private var previewSongID: Int?
    private var playbackRequestID = 0
    @Published private(set) var activePlaybackQueue: [DemoSong] = []
    private var autoAdvanceTask: Task<Void, Never>?
    private var shouldAutoAdvancePlayback = false
    private var recentPlaybackKeys: [String] = []
    private var recentPlaybackArtistKeys: [String] = []
    private var lastPlayerQueueCommitTime: TimeInterval = 0
    private let playbackSessionSalt = Double.random(in: 0..<10_000)
    private let homeFeedSessionSalt = Double.random(in: 0..<10_000)
    private let playbackQueueLimit = 24
    private let playbackQueueCommitCooldown: TimeInterval = 0.34
    private let playbackPrefetchLimit = 8
    private let homeFeedLimit = 220
    private let discoveryExtraSongLimit = 96
    private var nextPlaybackPrefetchPage = 1
    private var loadedPlaybackPrefetchPages = Set<Int>()
    private var lastRecommendationMood: HomeTimeMood?

    var discoverySongs: [DemoSong] {
        let baseSongs = librarySongs
        let recommendationSongs = aiRecommendationsEnabled ? recommendedSongs : []
        let spotifySongs = activeSpotifySongs
        return uniqueDiscoverySongs(
            from: homeFeedSongs + spotifySongs + interleavedDiscoverySongs(librarySongs: baseSongs, recommendedSongs: recommendationSongs) + discoveryExtraSongs
        )
    }

    var homeSurfaceSongs: [DemoSong] {
        let recommendationSongs = aiRecommendationsEnabled ? recommendedSongs : []
        let rotatedSpotifySongs = rotatedHomeSongs(activeSpotifySongs, salt: homeFeedSessionSalt)
        let rotatedLibrarySongs = rotatedHomeSongs(librarySongs, salt: homeFeedSessionSalt * 0.73 + 19)
        let spotifyFrontDoor = Array(rotatedSpotifySongs.prefix(28))
        let connectedSongs = uniqueDiscoverySongs(
            from: spotifyFrontDoor
                + homeFeedSongs
                + Array(rotatedSpotifySongs.dropFirst(28))
                + interleavedDiscoverySongs(librarySongs: rotatedLibrarySongs, recommendedSongs: recommendationSongs)
                + discoveryExtraSongs
        )

        if connectedSongs.isEmpty == false {
            return connectedSongs
        }

        return discoverySongs.filter(\.source.isRealDiscoverySource)
    }

    private var hasUsableSpotifySession: Bool {
        guard spotifyAccessToken.isEmpty == false else { return false }
        return spotifyTokenExpiresAt == 0 || spotifyTokenExpiresAt > Date().timeIntervalSince1970
    }

    private var activeSpotifySongs: [DemoSong] {
        hasUsableSpotifySession ? spotifySongs.filter(\.isHomeSurfacePlayable) : []
    }

    var visibleSpotifySongCount: Int {
        activeSpotifySongs.count
    }

    private func rotatedHomeSongs(_ songs: [DemoSong], salt: Double) -> [DemoSong] {
        guard songs.count > 1 else { return songs }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let offset = abs(Int(sin(Double(day) * 13.37 + salt) * 10_000)) % songs.count
        return Array(songs[offset...]) + Array(songs[..<offset])
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

    var isSpotifyReady: Bool {
        hasUsableSpotifySession
    }

    var isConnectedToAnyMusicService: Bool {
        isAppleMusicReady || isSpotifyReady
    }

    var spotifyStatusText: String {
        spotifyAccessToken.isEmpty ? "连接后导入你的 Spotify 歌单" : "已连接，可导入你的 Spotify 歌单"
    }

    func disconnectAppleMusic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        appleMusicConnected = false
        selectedApplePlaylistID = MusicPlaylistOption.allID
        librarySongs = []
        applePlaylists = []
        MPMediaLibrary.default().endGeneratingLibraryChangeNotifications()
        clearPlaybackIfNeeded(disconnectedSources: [.library])
        refreshHomeFeed()
        if aiRecommendationsEnabled {
            refreshRecommendations()
        }
        message = "已登出 Apple Music"
    }

    func disconnectSpotify() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        clearSpotifyPrivateData()
        clearPlaybackIfNeeded(disconnectedSources: [.spotify])
        refreshHomeFeed()
        if aiRecommendationsEnabled {
            refreshRecommendations()
        }
        message = "已登出 Spotify"
    }

    private func clearSpotifyPrivateData() {
        spotifyAccessToken = ""
        spotifyRefreshToken = ""
        spotifyTokenExpiresAt = 0
        selectedSpotifyPlaylistID = MusicPlaylistOption.allID
        spotifySongs = []
        spotifyPlaylists = []
    }

    private func runSpotifyPrivacyMigrationIfNeeded() {
        guard spotifyPrivacyResetVersion < requiredSpotifyPrivacyResetVersion else { return }
        clearSpotifyPrivateData()
        spotifyPrivacyResetVersion = requiredSpotifyPrivacyResetVersion
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
        initialLoadingFinishTask?.cancel()
        initialLoadingTimeoutTask?.cancel()
        initialLibraryLoadingStartedAt = Date()
        isInitialLibraryLoading = true
        scheduleInitialLibraryLoadingTimeout()
        runSpotifyPrivacyMigrationIfNeeded()
        if appleMusicConnected, MPMediaLibrary.authorizationStatus() == .authorized {
            loadAppleMusicLibrary()
        } else {
            appleMusicConnected = false
            refreshRecommendations()
        }
        refreshHomeFeed()
        scheduleStartupSpotifyRefreshIfNeeded()
        scheduleFullHomeFeedRefreshIfNeeded()
        syncPlaybackState()
    }

    private func finishInitialLibraryLoading() {
        initialLoadingTimeoutTask?.cancel()
        initialLoadingFinishTask?.cancel()
        let elapsed = Date().timeIntervalSince(initialLibraryLoadingStartedAt)
        let remainingDelay = max(0, 0.72 - elapsed)
        initialLoadingFinishTask = Task { @MainActor in
            if remainingDelay > 0 {
                try? await Task.sleep(for: .milliseconds(Int(remainingDelay * 1_000)))
            }
            guard Task.isCancelled == false else { return }
            isInitialLibraryLoading = false
        }
    }

    private func scheduleInitialLibraryLoadingTimeout() {
        initialLoadingTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard Task.isCancelled == false else { return }
            isInitialLibraryLoading = false
        }
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
        librarySongs = items.prefix(220).enumerated().map { index, item in
            let shouldLoadArtworkImmediately = index < 64
            let artworkImage = shouldLoadArtworkImmediately
                ? item.artwork?.image(at: CGSize(width: 220, height: 220))
                : nil
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
                lyricsText: index < 24 ? Self.extractLyrics(from: item) : nil,
                magicColor: Color(uiColor: magicColor),
                source: .library
            )
        }
        message = librarySongs.isEmpty
            ? "Apple Music 已授权，但没有读到已加入资料库的歌曲。请先在 Apple Music 里把歌曲添加到资料库，并确认系统设置里允许访问媒体与 Apple Music。"
            : "已读取 \(librarySongs.count) 首歌曲"
        refreshHomeFeed()
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
            refreshHomeFeed()
            refreshRecommendations()
        } else {
            recommendationTask?.cancel()
            recommendedSongs = []
            discoveryExtraSongs = []
            lastRecommendationMood = nil
            refreshHomeFeed()
        }
    }

    func refreshRecommendationsForCurrentTime() {
        guard aiRecommendationsEnabled else { return }
        let mood = HomeTimeMood.current
        guard lastRecommendationMood != mood else { return }
        refreshHomeFeed()
        refreshRecommendations()
    }

    func updateMoodPreference(energy: Double, warmth: Double) {
        let next = MusicMoodPreference(
            energy: min(1, max(-1, energy)),
            warmth: min(1, max(-1, warmth))
        )
        guard next != moodPreference else { return }
        moodPreference = next
        next.save()
        refreshHomeFeed()
        refreshRecommendations()
    }

    func loadMoreDiscoverySongs(page: Int) async -> [DemoSong] {
        let queries = moreDiscoveryQueries(page: page)
        let existingSongs = homeFeedSongs + librarySongs + recommendedSongs + discoveryExtraSongs
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

    func refreshSpotifySongsIfPossible(
        showMessage: Bool = false,
        maxCount: Int = 500,
        playlistLimit: Int = 50,
        playlistTrackLimit: Int = 40,
        hydrateLimit: Int = 96
    ) async {
        guard spotifyAccessToken.isEmpty == false else {
            spotifySongs = []
            spotifyPlaylists = []
            return
        }

        do {
            if spotifyTokenExpiresAt > 0,
               spotifyTokenExpiresAt - Date().timeIntervalSince1970 < 120,
               spotifyRefreshToken.isEmpty == false {
                let token = try await spotifyAuthenticator.refreshAccessToken(refreshToken: spotifyRefreshToken)
                spotifyAccessToken = token.accessToken
                spotifyRefreshToken = token.refreshToken ?? spotifyRefreshToken
                spotifyTokenExpiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn)).timeIntervalSince1970
            }

            let tokenForRequest = spotifyAccessToken
            let playlists = playlistLimit > 0
                ? try await SpotifyWebAPIClient.playlistOptions(accessToken: tokenForRequest, limit: playlistLimit)
                : spotifyPlaylists
            let drafts = try await SpotifyWebAPIClient.discoverySongDrafts(
                accessToken: tokenForRequest,
                maxCount: maxCount,
                playlistID: selectedSpotifyPlaylistID,
                playlistLimit: playlistLimit,
                playlistTrackLimit: playlistTrackLimit
            )
            guard spotifyAccessToken == tokenForRequest else { return }
            spotifyPlaylists = playlists
            spotifySongs = spotifySongs(from: drafts, artworkByID: [:], appleTrackByID: [:])
            hydrateSpotifyMetadata(for: drafts, hydrateLimit: hydrateLimit, tokenSnapshot: tokenForRequest)
            refreshHomeFeed()
            if aiRecommendationsEnabled {
                refreshRecommendations()
            }
            if showMessage {
                message = drafts.isEmpty ? "Spotify 已连接，但没有读到已收藏歌曲或歌单歌曲。" : "已导入 \(drafts.count) 首 Spotify 歌曲到首页"
            }
        } catch {
            clearSpotifyPrivateData()
            refreshHomeFeed()
            if aiRecommendationsEnabled {
                refreshRecommendations()
            }
            if showMessage {
                message = "Spotify 已连接，但暂时没拉到歌单：\(error.localizedDescription)"
            }
        }
    }

    func selectSpotifyPlaylist(_ optionID: String) async {
        selectedSpotifyPlaylistID = optionID
        await refreshSpotifySongsIfPossible(showMessage: true)
    }

    private func scheduleStartupSpotifyRefreshIfNeeded() {
        guard hasUsableSpotifySession else { return }
        spotifyStartupRefreshTask?.cancel()
        let tokenSnapshot = spotifyAccessToken
        spotifyStartupRefreshTask = Task { @MainActor in
            guard spotifyAccessToken == tokenSnapshot else { return }
            await refreshSpotifySongsIfPossible(maxCount: 36, playlistLimit: 0, playlistTrackLimit: 0, hydrateLimit: 12)
            guard spotifyAccessToken == tokenSnapshot else { return }
            scheduleFullSpotifyRefreshIfNeeded()
        }
    }

    private func scheduleFullSpotifyRefreshIfNeeded() {
        guard hasUsableSpotifySession else { return }
        spotifyFullRefreshTask?.cancel()
        let tokenSnapshot = spotifyAccessToken
        spotifyFullRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard spotifyAccessToken == tokenSnapshot else { return }
            isSpotifyLibraryRefreshing = true
            defer { isSpotifyLibraryRefreshing = false }
            await refreshSpotifySongsIfPossible(maxCount: 500, playlistLimit: 50, playlistTrackLimit: 40, hydrateLimit: 72)
        }
    }

    private func scheduleFullHomeFeedRefreshIfNeeded() {
        delayedHomeFeedRefreshTask?.cancel()
        delayedHomeFeedRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_300))
            guard isInitialLibraryLoading == false, Task.isCancelled == false else { return }
            refreshHomeFeed()
        }
    }

    func openSpotifySong(for song: DemoSong) {
        guard song.source == .spotify, let spotifyURI = song.spotifyURI else {
            message = "这首 Spotify 歌缺少打开链接。"
            return
        }

        stopPreviewPlayback(clearPlaybackState: true)
        MPMusicPlayerController.applicationMusicPlayer.stop()
        currentSong = nil
        playingSongID = nil
        isPlaying = false
        isPlaybackTransitioning = false
        showPlaybackLoadingToast = false

        let webURL = spotifyWebURL(from: spotifyURI)
        guard let appURL = URL(string: spotifyURI) else {
            openExternalURL(webURL, fallback: nil)
            return
        }

        UIApplication.shared.open(appURL, options: [:]) { [weak self] didOpen in
            guard didOpen == false else { return }
            Task { @MainActor in
                self?.openExternalURL(webURL, fallback: nil)
            }
        }
        message = "正在打开 Spotify：\(song.title)"
    }

    private func spotifyWebURL(from spotifyURI: String) -> URL? {
        guard spotifyURI.hasPrefix("spotify:track:") else { return nil }
        let trackID = String(spotifyURI.dropFirst("spotify:track:".count))
        return URL(string: "https://open.spotify.com/track/\(trackID)")
    }

    private func openExternalURL(_ url: URL?, fallback: URL?) {
        guard let url else {
            if let fallback {
                UIApplication.shared.open(fallback)
            }
            return
        }
        UIApplication.shared.open(url)
    }

    func startSpotifyPlayback(for song: DemoSong) async {
        guard song.source == .spotify, song.spotifyURI != nil else {
            message = "这首 Spotify 歌缺少播放链接。"
            return
        }
        guard spotifyAccessToken.isEmpty == false else {
            message = "请先连接 Spotify。"
            return
        }

        currentSong = song
        playingSongID = song.id
        isPlaying = false
        endPlaybackLoading()
        playingSongID = nil
        currentSong = nil
        message = "Spotify 播放暂时不可用，我先保住 Apple Music 播放不闪退。"
    }

    private func currentSpotifyAccessToken() async throws -> String {
        if spotifyTokenExpiresAt > 0,
           spotifyTokenExpiresAt - Date().timeIntervalSince1970 < 120,
           spotifyRefreshToken.isEmpty == false {
            let token = try await spotifyAuthenticator.refreshAccessToken(refreshToken: spotifyRefreshToken)
            spotifyAccessToken = token.accessToken
            spotifyRefreshToken = token.refreshToken ?? spotifyRefreshToken
            spotifyTokenExpiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn)).timeIntervalSince1970
        }
        return spotifyAccessToken
    }

    private func spotifySongs(
        from drafts: [SpotifySongDraft],
        artworkByID: [String: UIImage],
        appleTrackByID: [String: ITunesTrack]
    ) -> [DemoSong] {
        let palettes = DemoSong.library.map(\.colors)
        return drafts.enumerated().map { index, draft in
            let palette = palettes[(index + draft.title.count) % palettes.count]
            let matchedTrack = appleTrackByID[draft.id]
            let artworkImage = artworkByID[draft.id]
            let magicColor = artworkImage?.magicAverageColor ?? UIColor(songPalette: palette)
            return DemoSong(
                id: spotifySongID(for: draft, fallback: 700_000 + index),
                title: draft.title,
                artist: draft.artist,
                colors: palette,
                storeID: nil,
                previewURL: draft.previewURL ?? matchedTrack?.previewURL,
                spotifyURI: draft.spotifyURI,
                artworkImage: artworkImage,
                backdropImage: artworkImage?.playerBackdropImage,
                magicColor: Color(uiColor: magicColor),
                source: .spotify
            )
        }
    }

    private func hydrateSpotifyMetadata(
        for drafts: [SpotifySongDraft],
        initialAppleTrackByID: [String: ITunesTrack] = [:],
        hydrateLimit: Int = 96,
        tokenSnapshot: String
    ) {
        Task { @MainActor in
            guard spotifyAccessToken == tokenSnapshot else { return }
            let playbackDrafts = Array(drafts.prefix(hydrateLimit))
            let artworkDraftIDs = Set(drafts.prefix(min(24, hydrateLimit)).map(\.id))
            var artworkByID: [String: UIImage] = [:]
            var appleTrackByID = initialAppleTrackByID
            for (index, draft) in playbackDrafts.enumerated() {
                guard spotifyAccessToken == tokenSnapshot else { return }
                async let spotifyArtwork = artworkDraftIDs.contains(draft.id)
                    ? ITunesSearchClient.artworkImage(from: draft.artworkURL)
                    : nil
                let appleMatch: ITunesTrack?
                if let existingMatch = appleTrackByID[draft.id] {
                    appleMatch = existingMatch
                } else {
                    appleMatch = await bestAppleCatalogMatch(for: draft)
                }
                if let track = appleMatch {
                    appleTrackByID[draft.id] = track
                }
                var resolvedArtwork = await spotifyArtwork
                if resolvedArtwork == nil {
                    resolvedArtwork = await ITunesSearchClient.artworkImage(from: appleTrackByID[draft.id]?.artworkURL100)
                }
                if let image = resolvedArtwork {
                    artworkByID[draft.id] = image
                }
                if index < 16 || index.isMultiple(of: 8) || draft.id == playbackDrafts.last?.id {
                    guard spotifyAccessToken == tokenSnapshot else { return }
                    spotifySongs = spotifySongs(from: drafts, artworkByID: artworkByID, appleTrackByID: appleTrackByID)
                    refreshHomeFeed()
                }
            }
        }
    }

    private func bestAppleCatalogMatch(for draft: SpotifySongDraft) async -> ITunesTrack? {
        let query = "\(draft.title) \(draft.artist)"
        for storefront in uniqueQueries([AppleMusicStorefront.current, "us", "gb", "sg"]) {
            guard let tracks = try? await ITunesSearchClient.search(term: query, country: storefront, limit: 8) else { continue }
            let draftKey = normalizedSongKey(title: draft.title, artist: draft.artist)
            if let exact = tracks.first(where: { track in
                normalizedSongKey(title: track.trackName, artist: track.artistName) == draftKey
            }) {
                return exact
            }
            if let close = tracks.first(where: { track in
                normalizedTitleForRecommendation(track.trackName) == normalizedTitleForRecommendation(draft.title)
            }) {
                return close
            }
            if let first = tracks.first {
                return first
            }
        }
        return nil
    }

    private func resolvedSpotifySong(_ song: DemoSong) async -> DemoSong? {
        guard song.source == .spotify else { return nil }
        if song.isPlayable { return song }

        let draft = SpotifySongDraft(
            id: String(song.id),
            title: song.title,
            artist: song.artist,
            artworkURL: nil,
            previewURL: song.previewURL,
            spotifyURI: song.spotifyURI ?? "spotify:track:\(song.id)"
        )
        guard let track = await bestAppleCatalogMatch(for: draft),
              let previewURL = track.previewURL else {
            return nil
        }

        let downloadedArtwork = song.artworkImage == nil
            ? await ITunesSearchClient.artworkImage(from: track.artworkURL100)
            : nil
        let artworkImage = song.artworkImage ?? downloadedArtwork
        let magicColor = artworkImage?.magicAverageColor.map(Color.init(uiColor:)) ?? song.magicColor
        let resolvedSong = DemoSong(
            id: song.id,
            title: song.title,
            artist: song.artist,
            colors: song.colors,
            mediaItem: song.mediaItem,
            storeID: nil,
            previewURL: song.previewURL ?? previewURL,
            spotifyURI: song.spotifyURI,
            artworkImage: artworkImage,
            backdropImage: artworkImage?.playerBackdropImage ?? song.backdropImage,
            lyricsText: song.lyricsText,
            magicColor: magicColor,
            source: song.source
        )
        guard resolvedSong.isPlayable else { return nil }
        replaceSpotifySong(song, with: resolvedSong)
        return resolvedSong
    }

    private func replaceSpotifySong(_ oldSong: DemoSong, with newSong: DemoSong) {
        var didReplace = false
        spotifySongs = spotifySongs.map { candidate in
            guard isSameSong(candidate, oldSong) else { return candidate }
            didReplace = true
            return newSong
        }
        if didReplace == false {
            spotifySongs.insert(newSong, at: 0)
        }
        refreshHomeFeed()
    }

    private func spotifySongID(for draft: SpotifySongDraft, fallback: Int) -> Int {
        guard draft.id.isEmpty == false else { return fallback }
        let hash = draft.id.unicodeScalars.reduce(0) { partial, scalar in
            (partial * 131 + Int(scalar.value)) % 90_000
        }
        return 700_000 + hash
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
        queuePlayback(for: song, in: queueSongs, randomizeQueue: true)
    }

    func queuedNeighbor(for song: DemoSong, step: Int, fallbackSongs: [DemoSong]) -> DemoSong? {
        if let queuedSong = adjacentSong(to: song, step: step, in: activePlaybackQueue) {
            return queuedSong
        }
        let candidates = uniquePlayableSongs(from: fallbackSongs).filter { isSameSong($0, song) == false }
        return timeRecommendedRankedSongs(from: candidates).first
    }

    func playQueuedNeighbor(from song: DemoSong, step: Int, fallbackSongs: [DemoSong]) -> DemoSong? {
        let queue = activePlaybackQueue.isEmpty
            ? compactPlaybackQueueSnapshot(startingWith: song, in: fallbackSongs, randomizeTail: true)
            : activePlaybackQueue
        let nextSong: DemoSong?
        if step > 0 {
            let candidates = uniquePlayableSongs(from: queue).filter { isSameSong($0, song) == false }
            nextSong = timeRecommendedRankedSongs(from: candidates).first
        } else {
            nextSong = adjacentSong(to: song, step: step, in: queue)
        }
        guard let nextSong else { return nil }
        queuePlayback(for: nextSong, in: queue, randomizeQueue: step > 0)
        return nextSong
    }

    private func queuePlayback(for song: DemoSong, in queueSongs: [DemoSong]? = nil, randomizeQueue: Bool) {
        guard song.isPlayable else {
            if song.source == .spotify {
                queueSpotifyPlaybackAfterResolving(song, in: queueSongs, randomizeQueue: randomizeQueue)
                return
            }
            message = "这首是 AI 推荐，暂时没有可播放资源。"
            return
        }
        beginPlaybackLoading()
        queuedPlaybackTask?.cancel()
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        playbackPrefetchTask?.cancel()
        playbackRequestID &+= 1
        let requestID = playbackRequestID
        let queueSnapshot = compactPlaybackQueueSnapshot(startingWith: song, in: queueSongs, randomizeTail: randomizeQueue)
        activePlaybackQueue = queueSnapshot
        shouldAutoAdvancePlayback = true
        if playingSongID != song.id {
            playingSongID = song.id
        }
        if currentSong?.id != song.id {
            currentSong = song
        }
        rememberPlaybackSelection(song)
        if isPlaying == false {
            isPlaying = true
        }

        let delay = playbackQueueCommitDelay()
        queuedPlaybackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, requestID == playbackRequestID else { return }
            let player = MPMusicPlayerController.applicationMusicPlayer
            lastPlayerQueueCommitTime = Date().timeIntervalSinceReferenceDate
            setPlaybackQueue(on: player, startingWith: song, in: queueSnapshot)
            prepareAndStartPlayback(on: player, song: song, queueSongs: queueSnapshot, requestID: requestID)
        }
    }

    private func queueSpotifyPlaybackAfterResolving(_ song: DemoSong, in queueSongs: [DemoSong]?, randomizeQueue: Bool) {
        beginPlaybackLoading()
        queuedPlaybackTask?.cancel()
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        playbackPrefetchTask?.cancel()
        playbackRequestID &+= 1
        let requestID = playbackRequestID
        playingSongID = song.id
        currentSong = song
        isPlaying = true
        message = "正在准备 Spotify 歌曲..."

        queuedPlaybackTask = Task { @MainActor in
            guard let resolvedSong = await resolvedSpotifySong(song),
                  !Task.isCancelled,
                  requestID == playbackRequestID else {
                if requestID == playbackRequestID {
                    endPlaybackLoading(requestID: requestID)
                    isPlaying = false
                    playingSongID = nil
                    if song.spotifyURI != nil {
                        openSpotifySong(for: song)
                    } else {
                        message = "这首 Spotify 歌暂时没有可播放预览。"
                    }
                }
                return
            }

            let resolvedQueue = replacingSong(song, with: resolvedSong, in: queueSongs)
            queuedPlaybackTask = nil
            queuePlayback(for: resolvedSong, in: resolvedQueue, randomizeQueue: randomizeQueue)
        }
    }

    private func replacingSong(_ oldSong: DemoSong, with newSong: DemoSong, in queueSongs: [DemoSong]?) -> [DemoSong]? {
        guard let queueSongs else { return nil }
        var didReplace = false
        let resolvedSongs = queueSongs.map { candidate in
            guard isSameSong(candidate, oldSong) else { return candidate }
            didReplace = true
            return newSong
        }
        return didReplace ? resolvedSongs : [newSong] + resolvedSongs
    }

    private func playbackQueueCommitDelay() -> Int {
        let now = Date().timeIntervalSinceReferenceDate
        guard lastPlayerQueueCommitTime > 0 else { return 90 }
        let elapsed = now - lastPlayerQueueCommitTime
        let wait = max(0.09, playbackQueueCommitCooldown - elapsed)
        return Int((wait * 1000).rounded())
    }

    func togglePlayback(for song: DemoSong, in queueSongs: [DemoSong]? = nil) async {
        guard song.isPlayable else {
            message = "这首是 AI 推荐，暂时没有可播放资源。"
            return
        }
        if previewSongID == song.id, let previewAudioPlayer {
            if previewAudioPlayer.timeControlStatus == .playing {
                previewAudioPlayer.pause()
                autoAdvanceTask?.cancel()
                autoAdvanceTask = nil
                shouldAutoAdvancePlayback = false
                playingSongID = song.id
                currentSong = song
                isPlaying = false
                endPlaybackLoading()
                message = "已暂停：\(song.title)"
            } else {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                try? AVAudioSession.sharedInstance().setActive(true)
                previewAudioPlayer.play()
                shouldAutoAdvancePlayback = true
                playingSongID = song.id
                currentSong = song
                isPlaying = true
                endPlaybackLoading()
                message = "正在播放预览：\(song.title)"
            }
            return
        }
        let player = MPMusicPlayerController.applicationMusicPlayer
        if player.playbackState == .playing, isPlayerCurrentlyOn(song, player: player) {
            player.pause()
            autoAdvanceTask?.cancel()
            autoAdvanceTask = nil
            shouldAutoAdvancePlayback = false
            playingSongID = song.id
            currentSong = song
            isPlaying = false
            endPlaybackLoading()
            message = "已暂停：\(song.title)"
        } else if isPlayerCurrentlyOn(song, player: player) {
            player.play()
            shouldAutoAdvancePlayback = true
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
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
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
        if let previewAudioPlayer {
            isPlaying = isPlaybackTransitioning ? true : previewAudioPlayer.timeControlStatus == .playing
            return
        }

        let player = MPMusicPlayerController.applicationMusicPlayer
        let playbackState = player.playbackState
        isPlaying = isPlaybackTransitioning ? true : playbackState == .playing
        guard let item = player.nowPlayingItem else {
            guard isPlaybackTransitioning == false else { return }
            handlePlaybackStoppedIfNeeded(player: player)
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
        if (playbackState == .stopped || shouldAutoAdvanceFromPausedPlayback(player: player, item: item)),
           isPlaybackTransitioning == false {
            handlePlaybackStoppedIfNeeded(player: player)
        }
    }

    private func shouldAutoAdvanceFromPausedPlayback(player: MPMusicPlayerController, item: MPMediaItem) -> Bool {
        guard shouldAutoAdvancePlayback, player.playbackState == .paused else { return false }
        let duration = item.playbackDuration
        guard duration > 0 else { return false }
        let remaining = duration - player.currentPlaybackTime
        return remaining <= 1.2
    }

    private func handlePlaybackStoppedIfNeeded(player: MPMusicPlayerController) {
        guard shouldAutoAdvancePlayback, isPlaybackTransitioning == false else { return }
        guard autoAdvanceTask == nil else { return }
        guard let currentSong else { return }
        guard let nextSong = nextSongAfterPlaybackStop(currentSong) else {
            shouldAutoAdvancePlayback = false
            return
        }

        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, shouldAutoAdvancePlayback else { return }
            guard player.playbackState == .stopped || player.playbackState == .paused else { return }
            autoAdvanceTask = nil
            queuePlayback(for: nextSong, in: activePlaybackQueue, randomizeQueue: false)
        }
    }

    private func nextSongAfterPlaybackStop(_ song: DemoSong) -> DemoSong? {
        let queue = activePlaybackQueue.isEmpty ? playbackQueueSongs(startingWith: song, in: nil) : activePlaybackQueue
        let playableQueue = uniquePlayableSongs(from: queue)
        guard playableQueue.count > 1 else { return nil }
        let currentIndex = playableQueue.firstIndex(where: { candidate in
            candidate.id == song.id ||
            (candidate.storeID != nil && candidate.storeID == song.storeID) ||
            (candidate.mediaItem?.persistentID != nil && candidate.mediaItem?.persistentID == song.mediaItem?.persistentID)
        }) ?? 0
        let nextIndex = (currentIndex + 1) % playableQueue.count
        return playableQueue[nextIndex]
    }

    private func song(matching item: MPMediaItem) -> DemoSong? {
        let allSongs = homeFeedSongs + librarySongs + recommendedSongs + discoveryExtraSongs
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
            previewURL: song.previewURL,
            artworkImage: artworkImage,
            backdropImage: artworkImage?.playerBackdropImage ?? song.backdropImage,
            lyricsText: Self.extractLyrics(from: item) ?? song.lyricsText,
            magicColor: magicColor,
            source: song.source
        )
    }

    private func setPlaybackQueue(on player: MPMusicPlayerController, startingWith song: DemoSong, in queueSongs: [DemoSong]?) {
        stopPreviewPlayback(clearPlaybackState: false)
        if player.playbackState == .playing {
            player.pause()
        }
        prepareContinuousQueue(on: player, startingWith: song, in: queueSongs)
    }

    private func prepareAndStartPlayback(
        on player: MPMusicPlayerController,
        song: DemoSong,
        queueSongs: [DemoSong]?,
        requestID: Int
    ) {
        guard song.hasApplePlaybackSource else {
            if startPreviewPlayback(for: song, in: queueSongs, requestID: requestID) {
                return
            }
            endPlaybackLoading(requestID: requestID)
            isPlaying = false
            playingSongID = nil
            message = "这首歌暂时没有可播放预览。"
            return
        }

        player.prepareToPlay { [weak self] error in
            Task { @MainActor in
                guard let self, self.playingSongID == song.id, self.playbackRequestID == requestID else { return }
                if let error {
                    if self.startPreviewPlayback(for: song, in: queueSongs, requestID: requestID) {
                        return
                    }
                    self.endPlaybackLoading(requestID: requestID)
                    self.message = "加载这首歌有点慢：\(error.localizedDescription)"
                    return
                }
                player.play()
                self.schedulePlaybackPrefetch(startingWith: song, in: queueSongs, requestID: requestID)
                self.endPlaybackLoading(requestID: requestID)
                self.message = "正在播放：\(song.title)"
                self.previewPlaybackTask?.cancel()
                self.previewPlaybackTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1_500))
                    guard !Task.isCancelled,
                          self.playbackRequestID == requestID,
                          self.playingSongID == song.id,
                          self.previewSongID == nil,
                          player.playbackState != .playing else { return }
                    if self.startPreviewPlayback(for: song, in: queueSongs, requestID: requestID) == false {
                        self.endPlaybackLoading(requestID: requestID)
                        self.isPlaying = false
                        self.playingSongID = nil
                        self.message = "这首歌暂时没有可播放预览。"
                    }
                }
            }
        }
    }

    @discardableResult
    private func startPreviewPlayback(for song: DemoSong, in queueSongs: [DemoSong]?, requestID: Int? = nil) -> Bool {
        guard let previewURL = song.previewURL,
              let url = URL(string: previewURL) else {
            return false
        }
        if let requestID, requestID != playbackRequestID {
            return false
        }

        previewPlaybackTask?.cancel()
        let musicPlayer = MPMusicPlayerController.applicationMusicPlayer
        if musicPlayer.playbackState == .playing || musicPlayer.playbackState == .paused {
            musicPlayer.stop()
        }
        stopPreviewPlayback(clearPlaybackState: false)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        previewAudioPlayer = player
        previewSongID = song.id
        currentSong = song
        playingSongID = song.id
        isPlaying = true
        shouldAutoAdvancePlayback = true
        activePlaybackQueue = compactPlaybackQueueSnapshot(startingWith: song, in: queueSongs, randomizeTail: false)
        endPlaybackLoading(requestID: requestID)
        message = "正在播放预览：\(song.title)"

        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePreviewPlaybackEnded(songID: song.id)
            }
        }
        player.play()
        return true
    }

    private func stopPreviewPlayback(clearPlaybackState: Bool) {
        previewPlaybackTask?.cancel()
        previewPlaybackTask = nil
        previewAudioPlayer?.pause()
        previewAudioPlayer = nil
        previewSongID = nil
        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
            self.previewEndObserver = nil
        }
        if clearPlaybackState {
            playingSongID = nil
            isPlaying = false
            shouldAutoAdvancePlayback = false
        }
    }

    private func handlePreviewPlaybackEnded(songID: Int) {
        guard previewSongID == songID else { return }
        stopPreviewPlayback(clearPlaybackState: false)
        guard shouldAutoAdvancePlayback,
              let currentSong,
              let nextSong = nextSongAfterPlaybackStop(currentSong) else {
            shouldAutoAdvancePlayback = false
            isPlaying = false
            return
        }
        queuePlayback(for: nextSong, in: activePlaybackQueue, randomizeQueue: false)
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

    private func compactPlaybackQueueSnapshot(
        startingWith song: DemoSong,
        in queueSongs: [DemoSong]?,
        randomizeTail: Bool
    ) -> [DemoSong] {
        var snapshot = playbackQueueSongs(startingWith: song, in: queueSongs, randomizeTail: randomizeTail)
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
        let orderedQueue = orderedPlaybackQueue(startingWith: song, in: queueSongs)

        if let storeID = song.storeID, Self.isValidPlaybackStoreID(storeID) {
            let storeIDs = orderedQueue.compactMap { candidate -> String? in
                guard let candidateStoreID = candidate.storeID,
                      Self.isValidPlaybackStoreID(candidateStoreID) else { return nil }
                return candidateStoreID
            }
            player.setQueue(with: storeIDs.isEmpty ? [storeID] : storeIDs)
            return
        }

        if let mediaItem = song.mediaItem {
            let mediaItems = orderedQueue.compactMap(\.mediaItem)
            player.setQueue(with: MPMediaItemCollection(items: mediaItems.isEmpty ? [mediaItem] : mediaItems))
            player.nowPlayingItem = mediaItem
        }
    }

    private static func isValidPlaybackStoreID(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != "0" else { return false }
        return trimmed.allSatisfy(\.isNumber)
    }

    private func orderedPlaybackQueue(startingWith song: DemoSong, in queueSongs: [DemoSong]?) -> [DemoSong] {
        guard let queueSongs, queueSongs.isEmpty == false else {
            return playbackQueueSongs(startingWith: song, in: nil, randomizeTail: true)
        }

        var orderedSongs = uniquePlayableSongs(from: queueSongs)
        if orderedSongs.first.map({ isSameSong($0, song) }) == true {
            return Array(orderedSongs.prefix(playbackQueueLimit))
        }

        orderedSongs.removeAll { isSameSong($0, song) }
        orderedSongs.insert(song, at: 0)
        return Array(orderedSongs.prefix(playbackQueueLimit))
    }

    private func playbackQueueSongs(
        startingWith song: DemoSong,
        in queueSongs: [DemoSong]?,
        randomizeTail: Bool = false
    ) -> [DemoSong] {
        let source: [DemoSong]
        if let queueSongs, queueSongs.isEmpty == false {
            source = queueSongs
        } else {
            source = discoverySongs.isEmpty ? librarySongs : discoverySongs
        }

        let uniqueSongs = uniquePlayableSongs(from: source)
        guard let selectedIndex = uniqueSongs.firstIndex(where: { $0.id == song.id }) else {
            let songs = randomizeTail ? timeRecommendedPlaybackTail(from: uniqueSongs) : uniqueSongs
            return Array(songs.prefix(playbackQueueLimit))
        }

        if randomizeTail {
            let selectedSong = uniqueSongs[selectedIndex]
            let tail = timeRecommendedPlaybackTail(from: uniqueSongs.enumerated()
                .filter { $0.offset != selectedIndex }
                .map(\.element))
            return Array(([selectedSong] + tail).prefix(playbackQueueLimit))
        }

        let rotatedSongs = Array(uniqueSongs[selectedIndex...]) + Array(uniqueSongs[..<selectedIndex])
        return Array(rotatedSongs.prefix(playbackQueueLimit))
    }

    private func timeRecommendedPlaybackTail(from songs: [DemoSong]) -> [DemoSong] {
        weightedTimeShuffle(timeScoredSongs(from: songs))
    }

    private func timeRecommendedRankedSongs(from songs: [DemoSong]) -> [DemoSong] {
        timeScoredSongs(from: songs)
            .sorted { $0.score > $1.score }
            .map(\.song)
    }

    private func timeScoredSongs(from songs: [DemoSong]) -> [(song: DemoSong, score: Double)] {
        let mood = HomeTimeMood.current
        return songs.map { song -> (song: DemoSong, score: Double) in
            let timeScore = mood.score(song) * 2.8
            let tasteScore = moodPreference.score(song) * 0.45
            let recommendationBoost: Double = song.source == .recommendation ? 0.36 : 0
            let connectedSourceBoost: Double = (song.source == .spotify || song.source == .library) ? 0.12 : 0
            let sessionVariety = deterministicPlaybackJitter(for: song) * 0.52
            let recencyPenalty = playbackRecencyPenalty(for: song)
            return (song, timeScore + tasteScore + recommendationBoost + connectedSourceBoost + sessionVariety - recencyPenalty)
        }
    }

    private func rememberPlaybackSelection(_ song: DemoSong) {
        let songKey = normalizedSongKey(title: song.title, artist: song.artist)
        let artistKey = normalizedArtistForRecommendation(song.artist)
        recentPlaybackKeys.append(songKey)
        recentPlaybackArtistKeys.append(artistKey)
        recentPlaybackKeys = cappedUniqueRecentValues(recentPlaybackKeys, limit: 48)
        recentPlaybackArtistKeys = cappedUniqueRecentValues(recentPlaybackArtistKeys, limit: 24)
    }

    private func cappedUniqueRecentValues(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return Array(values.reversed().filter { seen.insert($0).inserted }.prefix(limit).reversed())
    }

    private func playbackRecencyPenalty(for song: DemoSong) -> Double {
        let songKey = normalizedSongKey(title: song.title, artist: song.artist)
        let artistKey = normalizedArtistForRecommendation(song.artist)
        let songPenalty: Double
        if let index = Array(recentPlaybackKeys.reversed()).firstIndex(of: songKey) {
            songPenalty = max(0.25, 3.2 - Double(index) * 0.16)
        } else {
            songPenalty = 0
        }

        let artistPenalty: Double
        if let index = Array(recentPlaybackArtistKeys.reversed()).firstIndex(of: artistKey) {
            artistPenalty = max(0.12, 1.1 - Double(index) * 0.08)
        } else {
            artistPenalty = 0
        }

        return songPenalty + artistPenalty
    }

    private func weightedTimeShuffle(_ songs: [(song: DemoSong, score: Double)]) -> [DemoSong] {
        var remaining = songs
        var result: [DemoSong] = []

        while remaining.isEmpty == false {
            let bestScore = remaining.map(\.score).max() ?? 0
            let weights = remaining.map { item in
                let normalizedScore = item.score - bestScore
                return max(0.18, exp(normalizedScore * 0.92)) + Double.random(in: 0...0.22)
            }
            let totalWeight = weights.reduce(0, +)
            var pick = Double.random(in: 0..<max(totalWeight, 0.001))
            var selectedIndex = remaining.startIndex

            for index in remaining.indices {
                pick -= weights[index]
                if pick <= 0 {
                    selectedIndex = index
                    break
                }
            }

            result.append(remaining.remove(at: selectedIndex).song)
        }

        return result
    }

    private func adjacentSong(to song: DemoSong, step: Int, in queue: [DemoSong]) -> DemoSong? {
        let playableQueue = uniquePlayableSongs(from: queue)
        guard playableQueue.count > 1, step != 0 else { return nil }
        let startIndex = playableQueue.firstIndex(where: { isSameSong($0, song) }) ?? 0
        for distance in 1...playableQueue.count {
            let rawIndex = startIndex + step * distance
            let index = (rawIndex % playableQueue.count + playableQueue.count) % playableQueue.count
            let candidate = playableQueue[index]
            if isSameSong(candidate, song) == false {
                return candidate
            }
        }
        return nil
    }

    private func isSameSong(_ lhs: DemoSong, _ rhs: DemoSong) -> Bool {
        if lhs.id == rhs.id { return true }
        if let lhsStoreID = lhs.storeID, lhsStoreID == rhs.storeID { return true }
        if let lhsMediaID = lhs.mediaItem?.persistentID,
           let rhsMediaID = rhs.mediaItem?.persistentID,
           lhsMediaID == rhsMediaID {
            return true
        }
        return normalizedSongKey(title: lhs.title, artist: lhs.artist) == normalizedSongKey(title: rhs.title, artist: rhs.artist)
    }

    private func deterministicPlaybackJitter(for song: DemoSong) -> Double {
        let key = normalizedSongKey(title: song.title, artist: song.artist)
        let keyValue = key.unicodeScalars.reduce(Double(song.id + 17)) { partial, scalar in
            partial + Double(scalar.value) * 0.017
        }
        let value = sin(keyValue * 12.9898 + playbackSessionSalt * 78.233) * 43_758.5453
        return value - floor(value)
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

    private func refreshHomeFeed() {
        homeFeedTask?.cancel()
        homeFeedRequestID &+= 1

        let seedSongs = homeFeedSeedSongs()
        if isInitialLibraryLoading, seedSongs.isEmpty {
            isHomeFeedRefreshing = false
            return
        }
        let sessionSalt = homeFeedSessionSalt
        let requestID = homeFeedRequestID
        let provisionalFeed = provisionalHomeFeedSongs(sessionSalt: sessionSalt)
        if homeFeedSongs.isEmpty, provisionalFeed.isEmpty == false {
            homeFeedSongs = provisionalFeed
        }
        if isInitialLibraryLoading, provisionalFeed.contains(where: \.isHomeSurfacePlayable) {
            finishInitialLibraryLoading()
        }

        isHomeFeedRefreshing = true
        homeFeedTask = Task { @MainActor in
            let feed = await fetchHomeFeedSongs(seedSongs: seedSongs, sessionSalt: sessionSalt, requestID: requestID)
            guard requestID == homeFeedRequestID else { return }
            isHomeFeedRefreshing = false
            finishInitialLibraryLoading()
            guard !Task.isCancelled else { return }
            if feed.isEmpty == false {
                homeFeedSongs = feed
            } else if homeFeedSongs.isEmpty {
                homeFeedSongs = provisionalFeed
            }
        }
    }

    private func provisionalHomeFeedSongs(sessionSalt: Double) -> [DemoSong] {
        let connectedSongs = uniqueDiscoverySongs(
            from: spotifySongs + librarySongs + recommendedSongs + discoveryExtraSongs
        )
        guard connectedSongs.isEmpty == false else { return [] }
        let profile = musicTasteProfile(from: connectedSongs)
        return Array(
            homeFeedShuffledSongs(
                connectedSongs,
                profile: profile,
                sessionSalt: sessionSalt
            )
            .prefix(homeFeedLimit)
        )
    }
    private func homeFeedSeedSongs() -> [DemoSong] {
        let connectedSongs = uniqueDiscoverySongs(
            from: spotifySongs + librarySongs + recommendedSongs + discoveryExtraSongs
        )
        return Array(connectedSongs.prefix(120))
    }

    private func fetchHomeFeedSongs(seedSongs: [DemoSong], sessionSalt: Double, requestID: Int) async -> [DemoSong] {
        let isStartupPass = isInitialLibraryLoading
        let storefronts = homeFeedStorefronts(sessionSalt: sessionSalt)
        let profile = musicTasteProfile(from: seedSongs)
        let spotifyLayer = homeFeedShuffledSongs(
            spotifySongs,
            profile: profile,
            sessionSalt: sessionSalt
        )
        let chartLayers = await fetchHomeChartLayers(
            storefronts: storefronts,
            seedSongs: seedSongs,
            profile: profile,
            maxStorefronts: isStartupPass ? 2 : 8
        )
        let chartSongs = uniqueDiscoverySongs(from: chartLayers.flatMap { $0 })
        let chartFeed = blendedHomeFeedSongs(
            layers: [spotifyLayer] + chartLayers,
            seedSongs: seedSongs,
            profile: profile,
            sessionSalt: sessionSalt
        )
        if requestID == homeFeedRequestID, Task.isCancelled == false, chartFeed.isEmpty == false {
            homeFeedSongs = chartFeed
            if isStartupPass {
                finishInitialLibraryLoading()
                return chartFeed
            }
        }
        let frontDoorSongs = await fetchAppleCatalogSongs(
            queries: Array(homeFeedFrontDoorQueries(from: profile).prefix(isStartupPass ? 4 : 12)),
            seedSongs: seedSongs + chartSongs,
            maxCount: isStartupPass ? 16 : 34,
            idBase: 1_100_000,
            profile: profile,
            storefronts: storefronts
        )
        if isStartupPass {
            let startupFeed = blendedHomeFeedSongs(
                layers: [spotifyLayer] + chartLayers + [frontDoorSongs],
                seedSongs: seedSongs,
                profile: profile,
                sessionSalt: sessionSalt
            )
            finishInitialLibraryLoading()
            return startupFeed
        }
        let latestSongs = await fetchAppleCatalogSongs(
            queries: homeFeedLatestQueries(from: profile),
            seedSongs: seedSongs + frontDoorSongs + chartSongs,
            maxCount: 36,
            idBase: 1_180_000,
            profile: profile,
            storefronts: Array(storefronts.reversed())
        )
        let tasteSongs = await fetchAppleCatalogSongs(
            queries: homeFeedTasteQueries(from: profile),
            seedSongs: seedSongs + frontDoorSongs + chartSongs + latestSongs,
            maxCount: 42,
            idBase: 1_220_000,
            profile: profile,
            storefronts: storefronts
        )

        return blendedHomeFeedSongs(
            layers: [spotifyLayer] + chartLayers + [latestSongs, frontDoorSongs, tasteSongs],
            seedSongs: seedSongs,
            profile: profile,
            sessionSalt: sessionSalt
        )
    }

    private func fetchHomeChartLayers(
        storefronts: [String],
        seedSongs: [DemoSong],
        profile: MusicTasteProfile,
        maxStorefronts: Int = 8
    ) async -> [[DemoSong]] {
        var layers: [[DemoSong]] = []
        var accumulatedSongs = seedSongs

        for (index, storefront) in storefronts.prefix(maxStorefronts).enumerated() {
            let layer = await fetchAppleChartSongs(
                storefront: storefront,
                seedSongs: accumulatedSongs,
                maxCount: 14,
                profile: profile,
                idBase: 1_040_000 + index * 10_000
            )
            guard layer.isEmpty == false else { continue }
            layers.append(layer)
            accumulatedSongs += layer
        }

        return layers
    }

    private func homeFeedStorefronts(sessionSalt: Double) -> [String] {
        let current = AppleMusicStorefront.current
        let defaults = [
            current, "us", "gb", "sg", "jp", "kr", "hk", "tw",
            "au", "ca", "fr", "de", "br", "mx", "th", "id"
        ]
        let calendar = Calendar.current
        let day = calendar.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let hourBucket = calendar.component(.hour, from: Date()) / 4

        return uniqueQueries(defaults).sorted {
            homeFeedJitter(for: "\($0)-\(sessionSalt)", day: day, hourBucket: hourBucket) >
            homeFeedJitter(for: "\($1)-\(sessionSalt)", day: day, hourBucket: hourBucket)
        }
    }

    private func homeFeedFrontDoorQueries(from profile: MusicTasteProfile) -> [String] {
        let year = Calendar.current.component(.year, from: Date())
        var queries = [
            "top hits \(year)",
            "viral pop \(year)",
            "new pop \(year)",
            "global hits \(year)",
            "fresh music \(year)",
            "trending pop songs \(year)",
            "new music daily \(year)",
            "fresh pop singles \(year)",
            "recommended pop music",
            "new pop songs \(year)",
            "trending songs \(year)"
        ]
        queries += moodQueries(for: profile.timeMood)
        queries += calendarHomeQueries()
        queries += moodPreference.queryHints
        return timeVariedHomeQueries(queries)
    }

    private func homeFeedLatestQueries(from profile: MusicTasteProfile) -> [String] {
        let year = Calendar.current.component(.year, from: Date())
        let latestAnchors = [
            "new music releases \(year)",
            "latest songs \(year)",
            "new singles \(year)",
            "new pop releases \(year)",
            "fresh new music \(year)",
            "new alternative pop \(year)",
            "new r&b songs \(year)",
            "new hip hop songs \(year)",
            "new mandopop songs \(year)",
            "new k-pop songs \(year)"
        ]
        return timeVariedHomeQueries(latestAnchors + latestReleaseQueries(from: profile) + profile.moodQueries)
    }

    private func homeFeedTasteQueries(from profile: MusicTasteProfile) -> [String] {
        let year = Calendar.current.component(.year, from: Date())
        let tasteAnchors = [
            "songs you should hear \(year)",
            "music recommendations \(year)",
            "fans also like songs",
            "fresh discovery songs \(year)",
            "undiscovered pop songs \(year)",
            "indie pop discoveries \(year)",
            "alternative discoveries \(year)",
            "playlist pop music \(year)",
            "radio hits \(year)",
            "new artist discoveries \(year)"
        ]
        return timeVariedHomeQueries(
            tasteAnchors
                + styleRecommendationQueries(from: profile)
                + artistRadioQueries(from: profile)
                + profile.seedRadioQueries
        )
    }

    private func calendarHomeQueries() -> [String] {
        let calendar = Calendar.current
        let date = Date()
        let weekday = calendar.component(.weekday, from: date)
        let month = calendar.component(.month, from: date)
        var queries: [String] = []

        if weekday == 1 || weekday == 7 {
            queries += ["weekend hits", "weekend pop playlist", "party pop songs"]
        } else {
            queries += ["weekday hits", "commute pop songs", "workday energy songs"]
        }

        switch month {
        case 3...5:
            queries += ["spring pop songs", "fresh spring music"]
        case 6...8:
            queries += ["summer hits", "summer pop songs", "sunny pop playlist"]
        case 9...11:
            queries += ["autumn pop songs", "cozy new music"]
        default:
            queries += ["winter pop songs", "late night winter songs"]
        }

        return queries
    }

    private func timeVariedHomeQueries(_ queries: [String]) -> [String] {
        let calendar = Calendar.current
        let day = calendar.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let hourBucket = calendar.component(.hour, from: Date()) / 4
        return uniqueQueries(queries)
            .sorted {
                homeFeedJitter(for: $0, day: day, hourBucket: hourBucket) >
                homeFeedJitter(for: $1, day: day, hourBucket: hourBucket)
            }
    }

    private func blendedHomeFeedSongs(
        layers: [[DemoSong]],
        seedSongs: [DemoSong],
        profile: MusicTasteProfile,
        sessionSalt: Double
    ) -> [DemoSong] {
        let preparedLayers = layers.map { layer in
            homeFeedShuffledSongs(layer, profile: profile, sessionSalt: sessionSalt)
        }
        .filter { $0.isEmpty == false }
        var cursors = Array(repeating: 0, count: preparedLayers.count)
        let pattern = preparedLayers.indices.flatMap { index in
            index == preparedLayers.startIndex ? [index, index] : [index]
        }
        var result: [DemoSong] = []
        var seenKeys = Set<String>()
        var seenStoreIDs = Set<String>()

        while result.count < homeFeedLimit {
            let before = result.count
            for layerIndex in pattern where preparedLayers.indices.contains(layerIndex) {
                var cursor = cursors[layerIndex]
                let layer = preparedLayers[layerIndex]
                while cursor < layer.count {
                    let song = layer[cursor]
                    cursor += 1
                    let key = normalizedSongKey(title: song.title, artist: song.artist)
                    guard seenKeys.insert(key).inserted else { continue }
                    if let storeID = song.storeID {
                        guard seenStoreIDs.insert(storeID).inserted else { continue }
                    }
                    result.append(song)
                    break
                }
                cursors[layerIndex] = cursor
                if result.count >= homeFeedLimit { break }
            }
            if result.count == before { break }
        }

        let connectedFallback = seedSongs.filter(\.source.isRealDiscoverySource)
        if result.count < 48 {
            for song in homeFeedShuffledSongs(connectedFallback, profile: profile, sessionSalt: sessionSalt) {
                let key = normalizedSongKey(title: song.title, artist: song.artist)
                guard seenKeys.insert(key).inserted else { continue }
                if let storeID = song.storeID {
                    guard seenStoreIDs.insert(storeID).inserted else { continue }
                }
                result.append(song)
                if result.count >= 48 { break }
            }
        }

        return Array(result.prefix(homeFeedLimit))
    }

    private func homeFeedShuffledSongs(
        _ songs: [DemoSong],
        profile: MusicTasteProfile,
        sessionSalt: Double
    ) -> [DemoSong] {
        let scoredSongs = songs.map { song -> (song: DemoSong, score: Double) in
            let timeScore = profile.timeMood.score(song) * 2.6
            let tasteScore = moodPreference.score(song) * 0.48
            let sourceBoost: Double
            switch song.source {
            case .recommendation: sourceBoost = 0.70
            case .spotify: sourceBoost = 0.45
            case .library: sourceBoost = 0.36
            case .demo: sourceBoost = -1.4
            case .placeholder: sourceBoost = -5
            }
            return (
                song,
                timeScore + tasteScore + sourceBoost + homeFeedJitter(for: song, sessionSalt: sessionSalt) * 1.35
            )
        }
        return weightedTimeShuffle(scoredSongs)
    }

    private func homeFeedJitter(for query: String, day: Int, hourBucket: Int) -> Double {
        let seed = query.unicodeScalars.reduce(Double(day * 31 + hourBucket * 17)) { partial, scalar in
            partial + Double(scalar.value) * 0.013
        }
        let value = sin(seed * 12.9898 + homeFeedSessionSalt * 78.233) * 43_758.5453
        return value - floor(value)
    }

    private func homeFeedJitter(for song: DemoSong, sessionSalt: Double) -> Double {
        let key = normalizedSongKey(title: song.title, artist: song.artist)
        let valueSeed = key.unicodeScalars.reduce(Double(song.id + 97)) { partial, scalar in
            partial + Double(scalar.value) * 0.021
        }
        let value = sin(valueSeed * 12.9898 + sessionSalt * 78.233) * 43_758.5453
        return value - floor(value)
    }

    private func refreshRecommendations() {
        guard aiRecommendationsEnabled else {
            recommendationTask?.cancel()
            recommendedSongs = []
            discoveryExtraSongs = []
            nextPlaybackPrefetchPage = 1
            loadedPlaybackPrefetchPages.removeAll()
            lastRecommendationMood = nil
            return
        }
        recommendationTask?.cancel()
        recommendedSongs = []
        discoveryExtraSongs = []
        nextPlaybackPrefetchPage = 1
        loadedPlaybackPrefetchPages.removeAll()
        lastRecommendationMood = HomeTimeMood.current

        let seedSongs = Array((spotifySongs + librarySongs).prefix(42))
        recommendationTask = Task { @MainActor in
            let recommendations = await fetchAppleCatalogRecommendations(from: seedSongs)
            guard !Task.isCancelled else { return }
            recommendedSongs = recommendations
            refreshHomeFeed()
            if recommendations.isEmpty == false {
                message = "AI 已根据\(HomeTimeMood.current.recommendationLabel)和 \(seedSongs.count) 首歌推荐 \(recommendations.count) 首"
            }
        }
    }

    private func fetchAppleCatalogRecommendations(from seedSongs: [DemoSong]) async -> [DemoSong] {
        let profile = musicTasteProfile(from: seedSongs)
        let timeMoodSongs = await fetchAppleCatalogSongs(
            queries: profile.moodQueries,
            seedSongs: seedSongs,
            maxCount: 18,
            idBase: 190_000,
            profile: profile
        )
        let artistRadioSongs = await fetchAppleCatalogSongs(
            queries: artistRadioQueries(from: profile),
            seedSongs: seedSongs + timeMoodSongs,
            maxCount: 20,
            idBase: 200_000,
            profile: profile
        )
        let styleSongs = await fetchAppleCatalogSongs(
            queries: styleRecommendationQueries(from: profile),
            seedSongs: seedSongs + timeMoodSongs + artistRadioSongs,
            maxCount: 24,
            idBase: 220_000,
            profile: profile
        )
        let latestSongs = await fetchAppleCatalogSongs(
            queries: latestReleaseQueries(from: profile),
            seedSongs: seedSongs + timeMoodSongs + artistRadioSongs + styleSongs,
            maxCount: 24,
            idBase: 240_000,
            profile: profile
        )
        let chartSongs = await fetchAppleChartSongs(
            seedSongs: seedSongs + timeMoodSongs + artistRadioSongs + styleSongs + latestSongs,
            maxCount: 18,
            profile: profile
        )
        return Array(uniqueDiscoverySongs(from: timeMoodSongs + artistRadioSongs + styleSongs + latestSongs + chartSongs).prefix(64))
    }

    private func fetchAppleChartSongs(
        storefront: String = "us",
        seedSongs: [DemoSong],
        maxCount: Int,
        profile: MusicTasteProfile,
        idBase: Int = 180_000
    ) async -> [DemoSong] {
        do {
            let tracks = try await AppleMusicRSSClient.topSongs(storefront: storefront, limit: 50)
            let rankedTracks = rankedRecommendationTracks(tracks, seedSongs: seedSongs, profile: profile)
            return await songs(
                from: rankedTracks,
                seedSongs: seedSongs,
                maxCount: maxCount,
                idBase: idBase
            )
        } catch {
            return []
        }
    }

    private func fetchAppleCatalogSongs(
        queries: [String],
        seedSongs: [DemoSong],
        maxCount: Int,
        idBase: Int,
        profile: MusicTasteProfile? = nil,
        storefronts: [String]? = nil
    ) async -> [DemoSong] {
        var results: [DemoSong] = []
        var seenKeys = Set(seedSongs.map { normalizedSongKey(title: $0.title, artist: $0.artist) })
        var seenStoreIDs = Set(seedSongs.compactMap(\.storeID))
        let searchStorefronts = storefronts?.filter { $0.isEmpty == false } ?? []

        for (queryIndex, query) in queries.enumerated() {
            guard results.count < maxCount else { break }
            do {
                let storefront = searchStorefronts.isEmpty
                    ? AppleMusicStorefront.current
                    : searchStorefronts[queryIndex % searchStorefronts.count]
                let tracks = try await ITunesSearchClient.search(term: query, country: storefront, limit: 22)
                let rankedTracks = profile.map {
                    rankedRecommendationTracks(tracks, seedSongs: seedSongs + results, profile: $0)
                } ?? tracks.prioritizingRecentReleases
                let songs = await songs(
                    from: rankedTracks,
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
                    id: recommendationSongID(for: track, idBase: idBase + results.count),
                    title: track.trackName,
                    artist: track.artistName,
                    colors: palette,
                    storeID: track.trackID,
                    previewURL: track.previewURL,
                    artworkImage: artworkImage,
                    backdropImage: artworkImage?.playerBackdropImage,
                    magicColor: Color(uiColor: magicColor),
                    source: .recommendation
                )
            )
        }

        return results
    }

    private func recommendationSongID(for track: ITunesTrack, idBase: Int) -> Int {
        let hash = track.trackID.unicodeScalars.reduce(0) { partial, scalar in
            (partial * 131 + Int(scalar.value)) % 9_000
        }
        return idBase + hash
    }

    private func moreDiscoveryQueries(page: Int) -> [String] {
        let profile = musicTasteProfile(
            from: Array((homeFeedSongs + spotifySongs + librarySongs + recommendedSongs).prefix(56))
        )
        let timeBased = profile.moodQueries
        let profileQueries = styleRecommendationQueries(from: profile) + artistRadioQueries(from: profile)
        let latestQueries = latestReleaseQueries(from: profile)
        let pool = (page % 2 == 0 ? timeBased + profileQueries + latestQueries : profileQueries + timeBased + latestQueries)
        let start = (page * 4) % max(pool.count, 1)
        return (0..<8).map { pool[(start + $0) % pool.count] }
    }

    private struct MusicTasteProfile {
        let seedCount: Int
        let timeMood: HomeTimeMood
        let topArtists: [String]
        let titleTokens: [String]
        let styleQueries: [String]
        let moodQueries: [String]
        let moodPositiveTokens: [String]
        let moodNegativeTokens: [String]
        let moodGenreHints: [String]
        let seedRadioQueries: [String]
    }

    private func musicTasteProfile(from songs: [DemoSong]) -> MusicTasteProfile {
        let realSongs = songs.filter { !$0.isPlaceholder }
        let mood = HomeTimeMood.current
        let artists = topArtists(from: realSongs, limit: 10)
        let titleTokens = weightedTokens(from: realSongs, limit: 12)
        let styleQueries = inferredTasteQueries(from: realSongs, titleTokens: titleTokens)
        let moodQueries = uniqueQueries(moodQueries(for: mood) + moodPreference.queryHints)
        let moodSignals = recommendationSignals(for: mood)
        let seedRadioQueries = realSongs.prefix(8).map { song in
            "\(song.title) \(song.artist) similar songs"
        }

        return MusicTasteProfile(
            seedCount: realSongs.count,
            timeMood: mood,
            topArtists: artists,
            titleTokens: titleTokens,
            styleQueries: styleQueries,
            moodQueries: moodQueries,
            moodPositiveTokens: moodSignals.positiveTokens,
            moodNegativeTokens: moodSignals.negativeTokens,
            moodGenreHints: moodSignals.genreHints,
            seedRadioQueries: seedRadioQueries
        )
    }

    private func artistRadioQueries(from profile: MusicTasteProfile) -> [String] {
        let artistQueries = profile.topArtists.prefix(8).flatMap { artist in
            [
                "\(artist) similar artists songs",
                "\(artist) radio songs",
                "\(artist) fans also like"
            ]
        }
        return Array(uniqueQueries(profile.seedRadioQueries + artistQueries).prefix(26))
    }

    private func latestReleaseQueries(from profile: MusicTasteProfile) -> [String] {
        let recentArtistQueries = profile.topArtists.prefix(8).flatMap { artist in
            [
                "\(artist) latest song",
                "\(artist) new single",
                "\(artist) new release"
            ]
        }
        let tokenQueries = profile.titleTokens.prefix(6).map { "\($0) new songs" }
        let styleLatestQueries = profile.styleQueries.flatMap { query in
            [
                "\(query) new releases",
                "\(query) latest songs"
            ]
        }
        return Array(uniqueQueries(recentArtistQueries + styleLatestQueries + tokenQueries).prefix(34))
    }

    private func styleRecommendationQueries(from profile: MusicTasteProfile) -> [String] {
        let tokenQueries = profile.titleTokens.prefix(8).flatMap { token in
            [
                "\(token) music recommendations",
                "\(token) similar songs"
            ]
        }
        return Array(uniqueQueries(profile.styleQueries + profile.moodQueries + tokenQueries).prefix(30))
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

    private func inferredTasteQueries(from songs: [DemoSong], titleTokens: [String]) -> [String] {
        let text = songs.map { "\($0.title) \($0.artist)" }.joined(separator: " ").lowercased()
        let tokenSet = Set(titleTokens)
        var queries: [String] = []

        func hasAny(_ terms: [String]) -> Bool {
            terms.contains { text.contains($0) || tokenSet.contains($0) }
        }

        if hasAny(["pop", "dance", "club", "brat", "hyperpop", "charli", "xcx", "dua", "madonna", "sabrina"]) {
            queries.append(contentsOf: ["dance pop discoveries", "electropop new music", "club pop tracks", "hyperpop new releases"])
        }
        if hasAny(["r&b", "rnb", "soul", "weeknd", "sza", "frank", "justin", "usher"]) {
            queries.append(contentsOf: ["alternative r&b discoveries", "smooth r&b pop", "night drive r&b"])
        }
        if hasAny(["rap", "hip", "hop", "trap", "drake", "kendrick", "tyler", "asap"]) {
            queries.append(contentsOf: ["melodic rap discoveries", "alternative hip hop new", "hip hop radio songs"])
        }
        if hasAny(["rock", "indie", "band", "guitar", "oasis", "u2", "radiohead"]) {
            queries.append(contentsOf: ["indie rock discoveries", "modern rock songs", "alternative favorites"])
        }
        if hasAny(["electronic", "house", "techno", "edm", "calvin", "fred", "ambient"]) {
            queries.append(contentsOf: ["electronic pop discoveries", "house music new", "chill electronic"])
        }
        if hasAny(["jazz", "piano", "garner", "coltrane", "swing", "bossa"]) {
            queries.append(contentsOf: ["modern jazz discoveries", "vocal jazz essentials", "piano jazz songs"])
        }
        if hasAny(["soundtrack", "score", "cinematic", "classical", "hisaishi", "movie"]) {
            queries.append(contentsOf: ["cinematic soundtrack", "modern classical calm", "film score essentials"])
        }

        if queries.isEmpty {
            queries = titleTokens.prefix(5).map { "\($0) songs" }
        }
        if queries.isEmpty {
            queries = ["new music discovery", "indie pop essentials", "fresh pop singles", "alternative discoveries"]
        }
        return uniqueQueries(queries)
    }

    private func moodQueries(for mood: HomeTimeMood) -> [String] {
        switch mood {
        case .morning:
            return [
                "morning acoustic pop",
                "bright indie pop",
                "coffeehouse pop",
                "sunny morning songs",
                "soft start songs",
                "morning commute music"
            ]
        case .afternoon:
            return [
                "workday energy songs",
                "feel good pop",
                "dance pop radio",
                "afternoon pop hits",
                "upbeat electronic pop",
                "fresh today hits"
            ]
        case .evening:
            return [
                "evening chill songs",
                "night drive songs",
                "cinematic pop",
                "alternative r&b evening",
                "indie evening playlist",
                "soft rock essentials"
            ]
        case .lateNight:
            return [
                "late night songs",
                "dream pop playlist",
                "after dark r&b",
                "ambient pop",
                "sleepy indie",
                "midnight slow songs"
            ]
        }
    }

    private func recommendationSignals(
        for mood: HomeTimeMood
    ) -> (positiveTokens: [String], negativeTokens: [String], genreHints: [String]) {
        switch mood {
        case .morning:
            return (
                ["morning", "sun", "sunny", "bright", "gold", "easy", "sweet", "fresh", "coffee", "acoustic", "spring", "light"],
                ["midnight", "dark", "after", "club", "party", "trap", "rage", "sleep", "sad"],
                ["acoustic", "singer", "pop", "indie", "folk", "soundtrack"]
            )
        case .afternoon:
            return (
                ["dance", "energy", "hot", "rush", "run", "work", "move", "light", "today", "fresh", "club", "beat"],
                ["sleep", "ambient", "slow", "lullaby", "alone", "sad", "dark"],
                ["pop", "dance", "electronic", "hip-hop", "alternative"]
            )
        case .evening:
            return (
                ["night", "drive", "blue", "moon", "evening", "cinematic", "dream", "smooth", "soft", "cruel", "haze"],
                ["morning", "coffee", "training", "workout", "kids", "holiday"],
                ["r&b", "soul", "alternative", "soundtrack", "rock", "pop"]
            )
        case .lateNight:
            return (
                ["midnight", "late", "slow", "sleep", "dream", "dark", "after", "alone", "eyes", "ambient", "quiet"],
                ["morning", "sunny", "party", "club", "hot", "rush", "workout", "dance"],
                ["ambient", "r&b", "soul", "classical", "soundtrack", "indie"]
            )
        }
    }

    private func weightedTokens(from songs: [DemoSong], limit: Int) -> [String] {
        let stopwords: Set<String> = [
            "the", "and", "with", "feat", "ft", "for", "from", "you", "your", "me", "my", "we", "our",
            "love", "song", "music", "official", "remix", "version", "edit", "live", "radio", "single",
            "album", "unknown", "artist"
        ]
        var counts: [String: Int] = [:]
        for song in songs {
            let words = "\(song.title) \(song.artist)"
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9&]+"#, with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
            for word in words where word.count >= 3 && stopwords.contains(word) == false {
                counts[word, default: 0] += song.source == .spotify ? 2 : 1
            }
        }
        return Array(counts
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .map(\.key)
            .prefix(limit))
    }

    private func rankedRecommendationTracks(
        _ tracks: [ITunesTrack],
        seedSongs: [DemoSong],
        profile: MusicTasteProfile
    ) -> [ITunesTrack] {
        let seedKeys = Set(seedSongs.map { normalizedSongKey(title: $0.title, artist: $0.artist) })
        let seedStoreIDs = Set(seedSongs.compactMap(\.storeID))
        let seedArtists = Set(seedSongs.map { normalizedArtistForRecommendation($0.artist) })
        let topArtists = Set(profile.topArtists.map { normalizedArtistForRecommendation($0) })
        let tokens = Set(profile.titleTokens)

        return tracks
            .filter { track in
                seedKeys.contains(normalizedSongKey(title: track.trackName, artist: track.artistName)) == false
                && seedStoreIDs.contains(track.trackID) == false
            }
            .prioritizingRecentReleases
            .sorted { lhs, rhs in
                let lhsScore = recommendationScore(
                    for: lhs,
                    seedArtists: seedArtists,
                    topArtists: topArtists,
                    tokens: tokens,
                    profile: profile
                )
                let rhsScore = recommendationScore(
                    for: rhs,
                    seedArtists: seedArtists,
                    topArtists: topArtists,
                    tokens: tokens,
                    profile: profile
                )
                if lhsScore == rhsScore {
                    return (lhs.releaseDate ?? .distantPast) > (rhs.releaseDate ?? .distantPast)
                }
                return lhsScore > rhsScore
            }
    }

    private func recommendationScore(
        for track: ITunesTrack,
        seedArtists: Set<String>,
        topArtists: Set<String>,
        tokens: Set<String>,
        profile: MusicTasteProfile
    ) -> Double {
        let artist = normalizedArtistForRecommendation(track.artistName)
        let title = normalizedTitleForRecommendation(track.trackName)
        let genre = track.primaryGenreName?.lowercased() ?? ""
        let searchable = "\(artist) \(title) \(genre)"
        var score = 0.0

        if topArtists.contains(artist) { score += 9 }
        if seedArtists.contains(artist) == false { score += 1.5 }
        for token in tokens where searchable.contains(token) {
            score += 2.4
        }
        for token in profile.moodPositiveTokens where searchable.contains(token) {
            score += 4.2
        }
        for token in profile.moodNegativeTokens where searchable.contains(token) {
            score -= 4.8
        }
        for hint in profile.moodGenreHints where genre.contains(hint) {
            score += 2.6
        }
        score += moodPreference.score(title: track.trackName, artist: track.artistName, rhythmEnergy: 0.50) * 2.1
        for query in profile.styleQueries where searchable.contains(query.components(separatedBy: " ").first ?? query) {
            score += 1.2
        }
        if let releaseDate = track.releaseDate {
            let days = Date().timeIntervalSince(releaseDate) / 86_400
            if days <= 45 { score += 8 }
            else if days <= 180 { score += 5 }
            else if days <= 730 { score += 2 }
        }
        if genre.contains("pop") || genre.contains("r&b") || genre.contains("hip-hop") || genre.contains("alternative") {
            score += 1
        }
        return score
    }

    private func uniqueQueries(_ queries: [String]) -> [String] {
        var seen = Set<String>()
        return queries.compactMap { query in
            let trimmed = query
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
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

    private func endPlaybackLoading(requestID: Int? = nil) {
        playbackLoadingTask?.cancel()
        playbackLoadingTask = nil
        playbackLoadingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            guard requestID == nil || requestID == playbackRequestID else { return }
            showPlaybackLoadingToast = false
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            guard requestID == nil || requestID == playbackRequestID else { return }
            isPlaybackTransitioning = false
            playbackLoadingTask = nil
        }
    }

    private func clearPlaybackIfNeeded(disconnectedSources: Set<DemoSongSource>) {
        activePlaybackQueue.removeAll { disconnectedSources.contains($0.source) }
        guard let currentSong, disconnectedSources.contains(currentSong.source) else { return }
        let player = MPMusicPlayerController.applicationMusicPlayer
        player.stop()
        stopPreviewPlayback(clearPlaybackState: true)
        self.currentSong = nil
        playingSongID = nil
        isPlaying = false
        isPlaybackTransitioning = false
        showPlaybackLoadingToast = false
        playbackPrefetchTask?.cancel()
        playbackPrefetchTask = nil
        playbackLoadingTask?.cancel()
        playbackLoadingTask = nil
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }

    func connectSpotify() async {
        guard !isConnectingSpotify else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        message = "正在连接 Spotify..."
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
            message = "Spotify 授权失败：\(error.localizedDescription)"
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

enum SpotifyAuthConfig {
    static let clientID = "bfa6de6c24d148db906470a5a4bf0345"
    static let redirectPort: UInt16 = 8888
    static let redirectPath = "/callback"
    static let redirectURI = "http://127.0.0.1:8888/callback"
    static let appRemoteRedirectURI = "musicfind://spotify-login-callback"
    static let scopes = [
        "user-library-read",
        "playlist-read-private"
    ]
}

private enum SpotifyPlaybackError: LocalizedError {
    case noActiveDevice
    case premiumRequired
    case missingPlaybackScope
    case playbackFailed(Int)

    var errorDescription: String? {
        switch self {
        case .noActiveDevice:
            return "没有可用的 Spotify 播放设备。"
        case .premiumRequired:
            return "Spotify 远程播放需要 Premium。"
        case .missingPlaybackScope:
            return "Spotify 缺少播放控制授权。"
        case let .playbackFailed(statusCode):
            return "Spotify 播放失败：\(statusCode)"
        }
    }
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
        playlistID: String,
        playlistLimit: Int = 50,
        playlistTrackLimit: Int = 40
    ) async throws -> [SpotifySongDraft] {
        if playlistID != MusicPlaylistOption.allID {
            return songDrafts(
                from: try await playlistTracks(accessToken: accessToken, playlistID: playlistID, limit: maxCount),
                maxCount: maxCount
            )
        }

        async let savedTracks = (try? savedTracks(accessToken: accessToken, limit: min(maxCount, 500))) ?? []
        async let playlistTracks = (try? tracksFromCurrentUserPlaylists(accessToken: accessToken, playlistLimit: playlistLimit, trackLimit: playlistTrackLimit)) ?? []
        let tracks = await savedTracks + playlistTracks
        return songDrafts(from: tracks, maxCount: maxCount)
    }

    private static func savedTracks(accessToken: String, limit: Int) async throws -> [SpotifyTrack] {
        var tracks: [SpotifyTrack] = []
        var offset = 0
        let pageSize = 50

        while tracks.count < limit {
            var components = URLComponents(string: "https://api.spotify.com/v1/me/tracks")
            components?.queryItems = [
                URLQueryItem(name: "limit", value: "\(min(pageSize, limit - tracks.count))"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
            guard let url = components?.url else { break }

            let response = try await get(SpotifySavedTracksResponse.self, url: url, accessToken: accessToken)
            let pageTracks = response.items.compactMap(\.track)
            guard pageTracks.isEmpty == false else { break }
            tracks.append(contentsOf: pageTracks)
            offset += pageSize
            if response.next == nil { break }
        }

        return tracks
    }

    private static func tracksFromCurrentUserPlaylists(
        accessToken: String,
        playlistLimit: Int,
        trackLimit: Int
    ) async throws -> [SpotifyTrack] {
        let playlists = try await currentUserPlaylists(accessToken: accessToken, limit: playlistLimit)
        var tracks: [SpotifyTrack] = []
        let batchSize = 8
        let selectedPlaylists = Array(playlists.prefix(playlistLimit))
        for batchStart in stride(from: 0, to: selectedPlaylists.count, by: batchSize) {
            guard tracks.count < playlistLimit * trackLimit else { break }
            let batch = Array(selectedPlaylists[batchStart..<min(batchStart + batchSize, selectedPlaylists.count)])
            let batchTracks = await withTaskGroup(of: [SpotifyTrack].self) { group in
                for playlist in batch {
                    group.addTask {
                        (try? await playlistTracks(accessToken: accessToken, playlistID: playlist.id, limit: trackLimit)) ?? []
                    }
                }

                var result: [SpotifyTrack] = []
                for await playlistTracks in group {
                    result.append(contentsOf: playlistTracks)
                }
                return result
            }
            tracks.append(contentsOf: batchTracks)
        }
        return tracks
    }

    private static func currentUserPlaylists(accessToken: String, limit: Int) async throws -> [SpotifyPlaylistSummary] {
        var playlists: [SpotifyPlaylistSummary] = []
        var offset = 0
        let pageSize = 50

        while playlists.count < limit {
            var components = URLComponents(string: "https://api.spotify.com/v1/me/playlists")
            components?.queryItems = [
                URLQueryItem(name: "limit", value: "\(min(pageSize, limit - playlists.count))"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
            guard let url = components?.url else { break }

            let response = try await get(SpotifyPlaylistsResponse.self, url: url, accessToken: accessToken)
            guard response.items.isEmpty == false else { break }
            playlists.append(contentsOf: response.items)
            offset += pageSize
            if response.next == nil { break }
        }

        return playlists
    }

    private static func playlistTracks(accessToken: String, playlistID: String, limit: Int) async throws -> [SpotifyTrack] {
        var tracks: [SpotifyTrack] = []
        var offset = 0
        let pageSize = 50

        while tracks.count < limit {
            var components = URLComponents(string: "https://api.spotify.com/v1/playlists/\(playlistID)/tracks")
            components?.queryItems = [
                URLQueryItem(name: "limit", value: "\(min(pageSize, limit - tracks.count))"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
            guard let url = components?.url else { break }

            let response = try await get(SpotifyPlaylistTracksResponse.self, url: url, accessToken: accessToken)
            let pageTracks = response.items.compactMap(\.track)
            guard pageTracks.isEmpty == false else { break }
            tracks.append(contentsOf: pageTracks)
            offset += pageSize
            if response.next == nil { break }
        }

        return tracks
    }

    private static func get<T: Decodable>(_ type: T.Type, url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 7)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw SpotifyAuthError.invalidTokenResponse
        }
        return try JSONDecoder().decode(type, from: data)
    }

    static func startPlayback(accessToken: String, trackURI: String, device: SpotifyDevice?) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/play")
        if let deviceID = device?.id {
            try await transferPlayback(accessToken: accessToken, deviceID: deviceID)
            components?.queryItems = [
                URLQueryItem(name: "device_id", value: deviceID)
            ]
        }
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SpotifyStartPlaybackRequest(uris: [trackURI]))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return }
        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 403:
            throw SpotifyPlaybackError.premiumRequired
        case 404:
            throw SpotifyPlaybackError.noActiveDevice
        default:
            throw SpotifyPlaybackError.playbackFailed(httpResponse.statusCode)
        }
    }

    static func preferredPlaybackDevice(accessToken: String) async throws -> SpotifyDevice? {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/devices") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        switch httpResponse.statusCode {
        case 200..<300:
            let response = try JSONDecoder().decode(SpotifyDevicesResponse.self, from: data)
            let playableDevices = response.devices.filter { $0.id != nil && $0.isRestricted == false }
            guard playableDevices.isEmpty == false else {
                throw SpotifyPlaybackError.noActiveDevice
            }
            return playableDevices.first { $0.type.localizedCaseInsensitiveContains("smartphone") && $0.isActive }
                ?? playableDevices.first { $0.type.localizedCaseInsensitiveContains("smartphone") }
                ?? playableDevices.first { $0.name.localizedCaseInsensitiveContains("iPhone") && $0.isActive }
                ?? playableDevices.first { $0.name.localizedCaseInsensitiveContains("iPhone") }
                ?? playableDevices.first { $0.isActive }
                ?? playableDevices.first
        case 403:
            throw SpotifyPlaybackError.missingPlaybackScope
        default:
            return nil
        }
    }

    private static func transferPlayback(accessToken: String, deviceID: String) async throws {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SpotifyTransferPlaybackRequest(deviceIDs: [deviceID], play: false))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return }
        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 403:
            throw SpotifyPlaybackError.premiumRequired
        case 404:
            throw SpotifyPlaybackError.noActiveDevice
        default:
            throw SpotifyPlaybackError.playbackFailed(httpResponse.statusCode)
        }
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
                    artworkURL: track.album?.images.first?.url,
                    previewURL: track.previewURL,
                    spotifyURI: "spotify:track:\(track.id)"
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
    let previewURL: String?
    let spotifyURI: String
}

private struct SpotifyStartPlaybackRequest: Encodable {
    let uris: [String]
}

private struct SpotifyTransferPlaybackRequest: Encodable {
    let deviceIDs: [String]
    let play: Bool

    private enum CodingKeys: String, CodingKey {
        case deviceIDs = "device_ids"
        case play
    }
}

private struct SpotifyDevicesResponse: Decodable {
    let devices: [SpotifyDevice]
}

private struct SpotifyDevice: Decodable {
    let id: String?
    let name: String
    let type: String
    let isActive: Bool
    let isRestricted: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case isActive = "is_active"
        case isRestricted = "is_restricted"
    }
}

private struct SpotifySavedTracksResponse: Decodable {
    let items: [SpotifySavedTrackItem]
    let next: String?
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
    let next: String?
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
    let next: String?
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
    let previewURL: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case artists
        case album
        case previewURL = "preview_url"
    }
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

    private let frameRate = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()
    private let minimumVisualMovement: CGFloat = 1.8
    private let sleepVelocity: CGFloat = 14

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
        let sizeChanged = abs(size.width - lastSize.width) > 4 || abs(size.height - lastSize.height) > 4
        guard size.width > 10, size.height > 10, force || sizeChanged || ids != lastSongIDs else { return }
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
        guard size.width > 10, size.height > 10, badges.isEmpty == false else { return }

        var next = badges
        var strongestImpact: CGFloat = 0
        var largestMovement: CGFloat = 0
        let gravity = motion.gravity
        let acceleration = CGPoint(x: CGFloat(gravity.x) * 420, y: CGFloat(-gravity.y) * 420)
        let dt: CGFloat = 1.0 / 20.0
        let damping: CGFloat = 0.94

        for index in next.indices {
            next[index].velocity.x = (next[index].velocity.x + acceleration.x * dt) * damping
            next[index].velocity.y = (next[index].velocity.y + acceleration.y * dt) * damping
            if abs(next[index].velocity.x) < sleepVelocity {
                next[index].velocity.x = 0
            }
            if abs(next[index].velocity.y) < sleepVelocity {
                next[index].velocity.y = 0
            }
            let previousPosition = next[index].position
            next[index].position.x += next[index].velocity.x * dt
            next[index].position.y += next[index].velocity.y * dt
            largestMovement = max(
                largestMovement,
                abs(next[index].position.x - previousPosition.x),
                abs(next[index].position.y - previousPosition.y)
            )

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

        guard largestMovement >= minimumVisualMovement || strongestImpact > 0 else { return }
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
        guard strength > 110 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCollisionHapticAt) > 0.35 else { return }
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
    private var lastPublishedGravity = CMAcceleration(x: 0, y: -0.75, z: 0)
    private var lastPublishTime = Date.distantPast
    private let gravityDeadband = 0.16
    private let minimumPublishInterval: TimeInterval = 1.0 / 8.0

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 20.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let nextGravity = motion.gravity
            let delta = max(
                abs(nextGravity.x - lastPublishedGravity.x),
                abs(nextGravity.y - lastPublishedGravity.y),
                abs(nextGravity.z - lastPublishedGravity.z)
            )
            let now = Date()
            guard delta >= gravityDeadband,
                  now.timeIntervalSince(lastPublishTime) >= minimumPublishInterval else { return }
            lastPublishedGravity = nextGravity
            lastPublishTime = now
            gravity = nextGravity
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
    let nextSong: DemoSong?
    let namespace: Namespace.ID
    let isPlayerCardVisible: Bool
    let isDropTargeted: Bool
    @Binding var playerPillFrame: CGRect
    let onPlayerTap: () -> Void
    let onTogglePlayback: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onMoodSeek: (CGFloat) -> Void

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
                nextSong: nextSong,
                playerPillFrame: $playerPillFrame,
                action: onPlayerTap,
                onTogglePlayback: onTogglePlayback,
                onPrevious: onPrevious,
                onNext: onNext,
                onMoodSeek: onMoodSeek
            )
            .id(nowPlaying.id)
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
    let preference: MusicMoodPreference
    @State private var particles: [MusicParticleSpec] = []

    private enum ParticleMood {
        case sparkle
        case square
        case triangle
        case mist
        case neon
    }

    private var rhythm: Double {
        song.rhythmEnergy
    }

    private var particleMood: ParticleMood {
        switch particleMoodIndex {
        case 1:
            return .square
        case 2:
            return .triangle
        case 3:
            return .mist
        case 4:
            return .neon
        default:
            return .sparkle
        }
    }

    private var particleMoodIndex: Int {
        let key = "\(song.title)|\(song.artist)"
        let folded = key.unicodeScalars.reduce(abs(song.id)) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return folded % 7
    }

    private var moodShapeShare: CGFloat {
        switch particleMood {
        case .sparkle:
            return 0.0
        case .square, .triangle:
            return 0.82
        case .mist:
            return 0.18
        case .neon:
            return 0.54
        }
    }

    private var sparkleCount: Int {
        Int(82 + rhythm * 60 + max(0, preference.energy) * 28 + abs(preference.warmth) * 12)
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
        .onChange(of: preference) { _, _ in
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
                case .mist:
                    style = .circle
                case .neon:
                    style = random(seed, 7.91) > 0.45 ? .diamond : .sparkle
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
                opacity: (mood == .mist ? 0.28 : 0.42) + Double(random(seed, 11.19)) * (mood == .mist ? 0.42 : 0.58),
                tint: tint,
                coreTint: coreTint,
                style: style,
                hasGlow: mood == .neon || random(seed, 13.63) > 0.76
            )
        }
    }

    private func particleTint(for seed: Double) -> Color {
        let pick = random(seed, 8.19)
        if pick < 0.16 {
            return preference.tint
        } else if pick < 0.30 {
            return Color(red: 0.62, green: 0.86, blue: 1.0)
        } else if pick < 0.44 {
            return Color(red: 1.0, green: 0.82, blue: 0.58)
        } else if pick < 0.56 {
            return Color(red: 0.82, green: 0.72, blue: 1.0)
        } else if pick < 0.68 {
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
        artworkCache.countLimit = 240
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
    let nextSong: DemoSong?
    @Binding var playerPillFrame: CGRect
    let action: () -> Void
    let onTogglePlayback: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onMoodSeek: (CGFloat) -> Void
    @State private var dragTranslation: CGFloat = 0
    @State private var committedArtworkOffset: CGFloat = 0
    @State private var isTextVisible = true
    @State private var isTouchActive = false
    @State private var touchLocation: CGPoint = CGPoint(x: 120, y: 26)
    @State private var tapGlowVisible = false
    @State private var dragHapticStep = 0
    @State private var touchBeganAt: Date?
    @State private var isMoodSeeking = false
    @State private var pendingSwipeTask: Task<Void, Never>?
    @State private var displayedSong: DemoSong?
    @State private var incomingSong: DemoSong?
    @State private var flipProgress: CGFloat = 0
    @State private var flipDirection: CGFloat = -1
    @State private var pendingFlipDirection: CGFloat = -1
    @State private var contentFlipTask: Task<Void, Never>?

    private var boundedDragOffset: CGFloat {
        max(-96, min(96, dragTranslation))
    }

    private var artworkOffset: CGFloat {
        committedArtworkOffset + boundedDragOffset
    }

    private var contentSwipeOffset: CGFloat {
        artworkOffset * 0.55
    }

    private var renderedSong: DemoSong {
        displayedSong ?? song
    }

    var body: some View {
        ZStack {
            PlayerPillGlassBackground(song: song, isActive: isActive, isPlaying: isPlaying)

            HStack(spacing: 10) {
                PlayerPillFlippingContent(
                    currentSong: renderedSong,
                    incomingSong: incomingSong,
                    flipProgress: flipProgress,
                    flipDirection: flipDirection,
                    isPlaying: isPlaying,
                    isPlaybackLoading: isPlaybackLoading,
                    swipeOffset: contentSwipeOffset,
                    dragFade: isTextVisible ? max(0.20, 1 - abs(boundedDragOffset) / 120) : 0
                )
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.16), value: isTextVisible)
                .animation(.smooth(duration: 0.12, extraBounce: 0.0), value: dragTranslation)
                .animation(.smooth(duration: 0.18, extraBounce: 0.0), value: committedArtworkOffset)

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
            .padding(.leading, 13)
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
                .stroke(.white.opacity(isActive ? 0.12 : 0.065), lineWidth: 0.7)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 27)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.20),
                            .white.opacity(0.05),
                            song.magicColor.opacity(0.12),
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
        .overlay {
            PlayerPillTouchGlow(
                song: song,
                location: touchLocation,
                isActive: isTouchActive,
                isReleasing: tapGlowVisible
            )
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if isMoodSeeking {
                Text(boundedDragOffset >= 0 ? "更兴奋" : "更安静")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 10)
                    .frame(height: 23)
                    .background(song.magicColor.opacity(0.34))
                    .clipShape(Capsule())
                    .offset(y: -28)
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .shadow(color: .white.opacity(0.06), radius: 14, y: -5)
        .shadow(color: song.magicColor.opacity(0.16), radius: 20, y: 6)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 9)
        .contentShape(RoundedRectangle(cornerRadius: 27))
        .scaleEffect(isTouchActive ? 1.045 : 1)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    updateTouchInteraction(value)
                }
                .onEnded { value in
                    finishTouchInteraction(value)
                }
        )
        .animation(.bouncy(duration: 0.30, extraBounce: 0.24), value: isTouchActive)
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
        .onAppear {
            if displayedSong == nil {
                displayedSong = song
            }
        }
        .onChange(of: song.id) { _, _ in
            runSongFlip(to: song)
        }
        .onDisappear {
            pendingSwipeTask?.cancel()
            pendingSwipeTask = nil
            contentFlipTask?.cancel()
            contentFlipTask = nil
        }
        .opacity(isPlayerCardVisible ? 0 : 1)
    }

    private func updateTouchInteraction(_ value: DragGesture.Value) {
        touchLocation = value.location

        if isTouchActive == false {
            isTouchActive = true
            tapGlowVisible = true
            pendingSwipeTask?.cancel()
            dragHapticStep = 0
            touchBeganAt = Date()
            isMoodSeeking = false
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.26)
        }

        dragTranslation = value.translation.width
        if let touchBeganAt,
           Date().timeIntervalSince(touchBeganAt) > 0.34,
           abs(value.translation.width) > 28,
           isMoodSeeking == false {
            isMoodSeeking = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.46)
        }
        let hapticStep = min(5, Int(abs(value.translation.width) / 22))
        if hapticStep > dragHapticStep {
            dragHapticStep = hapticStep
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.18 + CGFloat(hapticStep) * 0.035)
        }
    }

    private func finishTouchInteraction(_ value: DragGesture.Value) {
        let isTap = abs(value.translation.width) < 14 && abs(value.translation.height) < 14
        if isTap {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
            action()
            releaseTouchGlow()
            return
        }

        if isMoodSeeking, abs(value.translation.width) > 42 {
            onMoodSeek(value.translation.width)
            releaseTouchGlow()
            return
        }

        finishSwipe(value)
        releaseTouchGlow()
    }

    private func releaseTouchGlow() {
        dragTranslation = 0
        dragHapticStep = 0
        touchBeganAt = nil
        isMoodSeeking = false
        withAnimation(.smooth(duration: 0.18, extraBounce: 0.0)) {
            isTouchActive = false
        }
        withAnimation(.easeOut(duration: 0.34)) {
            tapGlowVisible = false
        }
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
        pendingFlipDirection = direction
        withAnimation(.easeOut(duration: 0.12)) {
            committedArtworkOffset = direction * 96
            isTextVisible = true
        }

        pendingSwipeTask?.cancel()
        pendingSwipeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard Task.isCancelled == false else { return }
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

    private func runSongFlip(to newSong: DemoSong) {
        guard displayedSong?.id != newSong.id else {
            incomingSong = nil
            flipProgress = 0
            return
        }
        contentFlipTask?.cancel()
        if displayedSong == nil {
            displayedSong = newSong
            return
        }

        flipDirection = pendingFlipDirection
        incomingSong = newSong
        flipProgress = 0
        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.02)) {
            flipProgress = 1
        }

        contentFlipTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard Task.isCancelled == false else { return }
            displayedSong = newSong
            incomingSong = nil
            flipProgress = 0
            contentFlipTask = nil
        }
    }
}

private struct PlayerPillFlippingContent: View {
    let currentSong: DemoSong
    let incomingSong: DemoSong?
    let flipProgress: CGFloat
    let flipDirection: CGFloat
    let isPlaying: Bool
    let isPlaybackLoading: Bool
    let swipeOffset: CGFloat
    let dragFade: CGFloat

    private var progress: CGFloat {
        min(1, max(0, flipProgress))
    }

    private var flipEnvelope: CGFloat {
        sin(progress * .pi)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                PlayerPillContentFace(
                    song: currentSong,
                    isPlaying: isPlaying,
                    isPlaybackLoading: isPlaybackLoading,
                    dragFade: dragFade,
                    isFlipping: incomingSong != nil
                )
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .opacity(Double(dragFade * (1 - progress * 0.82)))
                .scaleEffect(1 - progress * 0.035, anchor: .center)
                .rotation3DEffect(
                    .degrees(Double(-78 * progress * flipDirection)),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: flipDirection < 0 ? .leading : .trailing,
                    perspective: 0.76
                )
                .offset(x: swipeOffset - flipDirection * proxy.size.width * 0.035 * progress)

                if let incomingSong {
                    PlayerPillContentFace(
                        song: incomingSong,
                        isPlaying: isPlaying,
                        isPlaybackLoading: isPlaybackLoading,
                        dragFade: dragFade,
                        isFlipping: true
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                    .opacity(Double(dragFade * min(1, progress * 1.18)))
                    .scaleEffect(0.965 + progress * 0.035, anchor: .center)
                    .rotation3DEffect(
                        .degrees(Double(78 * (1 - progress) * flipDirection)),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: flipDirection < 0 ? .trailing : .leading,
                        perspective: 0.76
                    )
                    .offset(x: swipeOffset + flipDirection * proxy.size.width * 0.055 * (1 - progress))
                }

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(Double(0.09 * flipEnvelope)), lineWidth: 0.8)
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.white.opacity(Double(0.030 * flipEnvelope)))
                    }
                    .padding(.vertical, 5)
                    .offset(x: swipeOffset * 0.15)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 53)
    }
}

private struct PlayerPillContentFace: View {
    let song: DemoSong
    let isPlaying: Bool
    let isPlaybackLoading: Bool
    let dragFade: CGFloat
    let isFlipping: Bool

    var body: some View {
        HStack(spacing: 10) {
            PlayerPillArtworkThumb(song: song, isSpinning: isPlaying && isFlipping == false)
                .opacity(max(0.24, Double(dragFade)))

            PlayerPillSongText(song: song, isPlaying: isPlaying, isLoading: isPlaybackLoading)
                .opacity(Double(dragFade))
        }
        .padding(.trailing, 2)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(isFlipping ? 0.018 : 0))
        }
    }
}

private struct PlayerPillArtworkThumb: View {
    let song: DemoSong
    let isSpinning: Bool
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            if let artworkImage = PlayerArtworkWarmupCache.shared.artwork(for: song) ?? song.artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .rotationEffect(.degrees(rotation))
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
        .allowsHitTesting(false)
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

private struct PlayerPillTouchGlow: View {
    let song: DemoSong
    let location: CGPoint
    let isActive: Bool
    let isReleasing: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(isActive ? 0.34 : 0.22),
                            song.magicColor.opacity(isActive ? 0.24 : 0.16),
                            .white.opacity(isActive ? 0.08 : 0.04),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: isActive ? 330 : 370, height: isActive ? 190 : 220)
                .blur(radius: isActive ? 32 : 38)
                .opacity((isActive || isReleasing) ? 0.92 : 0)
                .position(location)
                .blendMode(.screen)

            RadialGradient(
                colors: [
                    .white.opacity(isActive ? 0.055 : 0),
                    song.magicColor.opacity(isActive ? 0.16 : 0),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 210
            )
                .frame(width: 380, height: 230)
                .blur(radius: 44)
                .opacity((isActive || isReleasing) ? 0.72 : 0)
                .position(location)
                .blendMode(.screen)
        }
        .animation(.smooth(duration: 0.18, extraBounce: 0.0), value: location)
        .animation(.bouncy(duration: 0.26, extraBounce: 0.18), value: isActive)
        .animation(.easeOut(duration: 0.34), value: isReleasing)
    }
}

private struct PlayerPillNextPeek: View {
    let song: DemoSong
    let reveal: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            if let artworkImage = PlayerArtworkWarmupCache.shared.artwork(for: song) ?? song.artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: song.magicColor.opacity(0.24), radius: 9)
        .offset(x: 19 - reveal * 10)
        .opacity(0.34 + reveal * 0.46)
        .scaleEffect(0.86 + reveal * 0.14)
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.16, extraBounce: 0.0), value: reveal)
    }
}

private struct PlayerPillGlassBackground: View {
    let song: DemoSong
    let isActive: Bool
    let isPlaying: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 27, style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(0.12)
            .overlay {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.015, green: 0.018, blue: 0.026).opacity(0.10),
                                Color(red: 0.006, green: 0.008, blue: 0.014).opacity(0.11),
                                .black.opacity(0.085)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                LinearGradient(
                    colors: [
                        .white.opacity(0.028),
                        .clear,
                        .black.opacity(0.030),
                        song.magicColor.opacity(0.055)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.plusLighter)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.042), location: 0.00),
                        .init(color: .white.opacity(0.010), location: 0.18),
                        .init(color: song.magicColor.opacity(isActive ? 0.080 : 0.052), location: 0.64),
                        .init(color: .black.opacity(0.022), location: 1.00)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.plusLighter)
            }
            .overlay {
                ZStack {
                    RadialGradient(
                        colors: [
                            .white.opacity(0.052),
                            .white.opacity(0.014),
                            .clear
                        ],
                        center: UnitPoint(x: 0.52, y: -0.08),
                        startRadius: 0,
                        endRadius: 170
                    )
                    .blur(radius: 18)
                    .blendMode(.plusLighter)

                    RadialGradient(
                        colors: [
                            song.magicColor.opacity(isActive ? 0.115 : 0.080),
                            song.magicColor.opacity(isActive ? 0.045 : 0.032),
                            .clear
                        ],
                        center: UnitPoint(x: 0.50, y: 0.22),
                        startRadius: 0,
                        endRadius: 190
                    )
                    .blur(radius: 24)
                    .blendMode(.plusLighter)
                }
            }
            .overlay(alignment: .topLeading) {
                RadialGradient(
                    colors: [
                        .white.opacity(0.052),
                        .white.opacity(0.016),
                        .clear
                    ],
                    center: .center,
                    startRadius: 18,
                    endRadius: 150
                )
                    .frame(width: 250, height: 112)
                    .offset(x: -50, y: -44)
                    .blur(radius: 34)
                    .blendMode(.screen)
            }
            .overlay(alignment: .bottomTrailing) {
                RadialGradient(
                    colors: [
                        song.magicColor.opacity(0.125),
                        song.magicColor.opacity(0.045),
                        .clear
                    ],
                    center: .center,
                    startRadius: 24,
                    endRadius: 180
                )
                    .frame(width: 320, height: 140)
                    .offset(x: 60, y: 40)
                    .blur(radius: 42)
                    .blendMode(.screen)
            }
            .overlay(alignment: .leading) {
                RadialGradient(
                    colors: [
                        song.magicColor.opacity(0.070),
                        .clear
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: 140
                )
                    .frame(width: 240, height: 130)
                    .offset(x: -100)
                    .blur(radius: 46)
                    .blendMode(.screen)
            }
            .overlay {
                PlayerPillOrbitingRimLight(song: song, isPlaying: isPlaying, isActive: isActive)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                PlayerPillRhythmLights(song: song, isPlaying: isPlaying)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .allowsHitTesting(false)
            }
    }
}

private struct PlayerPillOrbitingRimLight: View {
    let song: DemoSong
    let isPlaying: Bool
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let speed = 0.055 + song.rhythmEnergy * 0.025
            let progress = positiveModulo(time * speed + randomUnit(salt: 0.43), 1)
            let counterProgress = positiveModulo(1 - time * (speed * 0.62) + randomUnit(salt: 1.91), 1)
            let pulse = 0.68 + 0.32 * sin(time * 0.9 + randomUnit(salt: 2.71) * .pi * 2)
            let activeOpacity = isPlaying ? 1.0 : (isActive ? 0.22 : 0.10)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)
                let primaryPoint = capsulePoint(progress: progress, width: width, height: height)
                let secondaryPoint = capsulePoint(progress: counterProgress, width: width, height: height)
                let tertiaryPoint = capsulePoint(progress: positiveModulo(progress + 0.42, 1), width: width, height: height)
                let angle = progress * 360
                let reverseAngle = -counterProgress * 360 + 130

                ZStack {
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .clear,
                                    song.magicColor.opacity(0.12 * activeOpacity),
                                    .white.opacity(0.30 * activeOpacity),
                                    song.magicColor.opacity(0.42 * activeOpacity),
                                    .clear,
                                    .clear
                                ],
                                center: .center,
                                angle: .degrees(angle)
                            ),
                            lineWidth: 7.5
                        )
                        .padding(2)
                        .blur(radius: 9)
                        .blendMode(.plusLighter)
                        .opacity(0.78)

                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.24 * activeOpacity),
                                    song.magicColor.opacity(0.34 * activeOpacity),
                                    .clear,
                                    song.magicColor.opacity(0.18 * activeOpacity),
                                    .clear
                                ],
                                center: .center,
                                angle: .degrees(reverseAngle)
                            ),
                            lineWidth: 2.1
                        )
                        .padding(3)
                        .blur(radius: 2.4)
                        .blendMode(.screen)
                        .opacity(0.72)

                    orbitGlow(
                        at: primaryPoint,
                        width: width * 0.34,
                        height: height * 1.12,
                        opacity: 0.70 * activeOpacity * pulse,
                        whiteStrength: 0.26,
                        colorStrength: 0.58
                    )

                    orbitGlow(
                        at: secondaryPoint,
                        width: width * 0.24,
                        height: height * 0.90,
                        opacity: 0.48 * activeOpacity,
                        whiteStrength: 0.16,
                        colorStrength: 0.38
                    )

                    orbitGlow(
                        at: tertiaryPoint,
                        width: width * 0.20,
                        height: height * 0.70,
                        opacity: 0.32 * activeOpacity,
                        whiteStrength: 0.10,
                        colorStrength: 0.30
                    )
                }
                .frame(width: width, height: height)
                .opacity(isPlaying ? 1 : 0.56)
                .animation(.easeOut(duration: 0.22), value: isPlaying)
            }
        }
    }

    private func orbitGlow(
        at point: CGPoint,
        width: CGFloat,
        height: CGFloat,
        opacity: Double,
        whiteStrength: Double,
        colorStrength: Double
    ) -> some View {
        RadialGradient(
            colors: [
                .white.opacity(whiteStrength),
                song.magicColor.opacity(colorStrength),
                song.magicColor.opacity(colorStrength * 0.30),
                .clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: width * 0.46
        )
        .frame(width: width, height: height)
        .position(point)
        .blur(radius: 14)
        .blendMode(.plusLighter)
        .opacity(opacity)
    }

    private func capsulePoint(progress: Double, width: CGFloat, height: CGFloat) -> CGPoint {
        let radius = height / 2
        let straight = max(width - height, 1)
        let arcLength = Double.pi * Double(radius)
        let perimeter = Double(straight * 2) + arcLength * 2
        let distance = progress * perimeter

        if distance < Double(straight) {
            return CGPoint(x: radius + CGFloat(distance), y: 1.5)
        }

        if distance < Double(straight) + arcLength {
            let arcProgress = (distance - Double(straight)) / arcLength
            let angle = -Double.pi / 2 + arcProgress * Double.pi
            return CGPoint(
                x: width - radius + CGFloat(cos(angle)) * radius,
                y: radius + CGFloat(sin(angle)) * radius
            )
        }

        if distance < Double(straight * 2) + arcLength {
            let lineProgress = distance - Double(straight) - arcLength
            return CGPoint(x: width - radius - CGFloat(lineProgress), y: height - 1.5)
        }

        let arcProgress = (distance - Double(straight * 2) - arcLength) / arcLength
        let angle = Double.pi / 2 + arcProgress * Double.pi
        return CGPoint(
            x: radius + CGFloat(cos(angle)) * radius,
            y: radius + CGFloat(sin(angle)) * radius
        )
    }

    private func randomUnit(salt: Double) -> Double {
        let value = sin(Double(song.id) * 0.071 + salt * 78.233) * 43_758.5453
        return value - floor(value)
    }

    private func positiveModulo(_ value: Double, _ divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private struct PlayerPillRhythmLights: View {
    let song: DemoSong
    let isPlaying: Bool

    private let bars = Array(0..<10)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let fallbackTime = timeline.date.timeIntervalSinceReferenceDate
            let playbackTime = currentPlaybackTime(fallbackTime: fallbackTime)
            let bpm = playbackBPM(for: song)
            let beatPosition = playbackTime * bpm / 60.0
            let slidePosition = beatPosition * 0.18
            let orbitProgress = positiveModulo(beatPosition * 0.048 + randomUnit(index: 2000, salt: 6.41), 1)
            let orbitAngle = orbitProgress * .pi * 2
            let reverseOrbitAngle = -orbitAngle + .pi * 0.72
            let beatPulse = pow(max(0, sin(beatPosition * .pi * 2)), 2)
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)
                let horizontalWave = sin(slidePosition * .pi * 2)
                let verticalWave = sin(slidePosition * .pi * 2 - .pi / 3)
                let secondaryWave = sin(slidePosition * .pi * 4 + .pi / 4)
                let counterWave = sin(slidePosition * .pi * 2 + .pi * 0.82)
                let ribbonWave = sin(slidePosition * .pi * 2 - .pi * 0.58)
                let glowCenterX = 0.50 + CGFloat(horizontalWave) * 0.30
                let glowCenterY = 0.82 - CGFloat(verticalWave) * 0.24
                let counterCenterX = 0.50 + CGFloat(counterWave) * 0.24
                let counterCenterY = 0.84 + CGFloat(ribbonWave) * 0.18
                let orbitX = width * (0.50 + CGFloat(cos(orbitAngle)) * 0.43)
                let orbitY = height * (0.54 + CGFloat(sin(orbitAngle)) * 0.38)
                let reverseOrbitX = width * (0.50 + CGFloat(cos(reverseOrbitAngle)) * 0.40)
                let reverseOrbitY = height * (0.54 + CGFloat(sin(reverseOrbitAngle)) * 0.34)
                let orbitDegrees = orbitAngle * 180 / .pi
                let ribbonLoopBlend = 0.55 + 0.45 * loopEnvelope(progress: orbitProgress)

                ZStack(alignment: .bottomLeading) {
                    Capsule()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .clear,
                                    song.magicColor.opacity(isPlaying ? 0.10 : 0),
                                    .white.opacity(isPlaying ? 0.26 : 0),
                                    song.magicColor.opacity(isPlaying ? 0.28 : 0),
                                    .clear,
                                    .clear
                                ],
                                center: .center,
                                angle: .degrees(orbitDegrees)
                            ),
                            lineWidth: height * 0.28
                        )
                        .frame(width: width * 0.94, height: height * 0.70)
                        .offset(x: width * 0.03, y: height * 0.15)
                        .blur(radius: 12)
                        .blendMode(.plusLighter)
                        .opacity(isPlaying ? 0.72 : 0)

                    RadialGradient(
                        colors: [
                            .white.opacity(isPlaying ? 0.29 + CGFloat(beatPulse) * 0.05 : 0),
                            song.magicColor.opacity(isPlaying ? 0.48 : 0),
                            song.magicColor.opacity(isPlaying ? 0.18 : 0),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.34
                    )
                    .frame(width: width * 0.58, height: height * 1.62)
                    .position(x: orbitX, y: orbitY)
                    .blur(radius: 17)
                    .blendMode(.plusLighter)
                    .opacity(isPlaying ? 0.88 : 0)

                    RadialGradient(
                        colors: [
                            song.magicColor.opacity(isPlaying ? 0.34 : 0),
                            .white.opacity(isPlaying ? 0.15 : 0),
                            song.magicColor.opacity(isPlaying ? 0.12 : 0),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.26
                    )
                    .frame(width: width * 0.46, height: height * 1.28)
                    .position(x: reverseOrbitX, y: reverseOrbitY)
                    .blur(radius: 20)
                    .blendMode(.plusLighter)
                    .opacity(isPlaying ? 0.58 : 0)

                    ForEach(bars, id: \.self) { index in
                        let phaseA = randomPhase(index: index, salt: 0.13)
                        let phaseB = randomPhase(index: index, salt: 0.47)
                        let phaseC = randomPhase(index: index, salt: 0.79)
                        let loopPhase = randomUnit(index: index, salt: 4.19)
                        let speedA = 0.62 + randomUnit(index: index, salt: 1.11) * 0.68
                        let speedB = 0.88 + randomUnit(index: index, salt: 1.73) * 0.74
                        let speedC = 0.48 + randomUnit(index: index, salt: 2.31) * 0.82
                        let loopSpeed = 0.034 + randomUnit(index: index, salt: 4.73) * 0.046
                        let driftAmount = 0.040 + randomUnit(index: index, salt: 2.89) * 0.082
                        let verticalAmount = 0.060 + randomUnit(index: index, salt: 3.37) * 0.135
                        let lanePhase = slidePosition * .pi * 2 * speedA + phaseA
                        let laneWave = sin(lanePhase)
                        let laneSwell = sin(slidePosition * .pi * 2 * speedB + phaseB)
                        let laneDrift = sin(slidePosition * .pi * 2 * speedC + phaseC)
                        let loopProgress = positiveModulo(beatPosition * loopSpeed + loopPhase, 1)
                        let loopBlend = loopEnvelope(progress: loopProgress)
                        let loopAngle = loopSpinAngle(progress: loopProgress, phase: phaseC)
                        let loopRadiusX = width * (0.155 + CGFloat(randomUnit(index: index, salt: 5.37)) * 0.095)
                        let loopRadiusY = height * (0.220 + CGFloat(randomUnit(index: index, salt: 5.91)) * 0.170)
                        let loopX = cos(loopAngle) * Double(loopRadiusX) * loopBlend
                        let loopY = sin(loopAngle) * Double(loopRadiusY) * loopBlend
                        let x = width * (0.04 + CGFloat(index) * 0.102)
                            + CGFloat(horizontalWave) * width * 0.135
                            + CGFloat(laneDrift) * width * CGFloat(driftAmount)
                            + CGFloat(loopX)
                        let glowHeight = height * (0.30 + CGFloat(laneWave + 1) * 0.10 + CGFloat(laneSwell + 1) * 0.035)
                        let glowWidth = width * (0.145 + CGFloat(laneSwell + 1) * 0.025)
                        let opacity = isPlaying ? (0.38 + CGFloat(laneWave + 1) * 0.045 + CGFloat(beatPulse) * 0.035) : 0
                        let verticalOffset = height * (
                            0.47
                            - CGFloat(verticalWave) * 0.28
                            - CGFloat(laneWave) * CGFloat(verticalAmount)
                            + CGFloat(laneDrift) * 0.070
                        ) + CGFloat(loopY)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.41),
                                        song.magicColor.opacity(0.64),
                                        song.magicColor.opacity(0.32),
                                        .clear
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: glowWidth, height: glowHeight)
                            .blur(radius: 18)
                            .opacity(opacity)
                            .offset(x: x - glowWidth / 2, y: verticalOffset)
                            .blendMode(.plusLighter)
                    }

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    song.magicColor.opacity(isPlaying ? 0.28 : 0),
                                    .white.opacity(isPlaying ? 0.13 : 0),
                                    song.magicColor.opacity(isPlaying ? 0.18 : 0),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * 0.68, height: height * 0.18)
                        .rotationEffect(.degrees(-8 + ribbonWave * 8 + ribbonLoopBlend * orbitDegrees))
                        .offset(
                            x: width * (0.16 + CGFloat(horizontalWave) * 0.20 + CGFloat(cos(orbitAngle) * ribbonLoopBlend) * 0.095),
                            y: height * (0.50 + CGFloat(ribbonWave) * 0.20 + CGFloat(sin(orbitAngle) * ribbonLoopBlend) * 0.145)
                        )
                        .blur(radius: 14)
                        .blendMode(.plusLighter)
                        .opacity(isPlaying ? 0.82 : 0)

                    RadialGradient(
                        colors: [
                            .white.opacity(isPlaying ? 0.15 : 0),
                            song.magicColor.opacity(isPlaying ? 0.36 : 0),
                            song.magicColor.opacity(isPlaying ? 0.12 : 0),
                            .clear
                        ],
                        center: UnitPoint(x: glowCenterX, y: glowCenterY),
                        startRadius: 4,
                        endRadius: width * (0.54 + CGFloat(secondaryWave + 1) * 0.06)
                    )
                    .frame(width: width, height: height * 0.92)
                    .offset(y: height * 0.30)
                    .blur(radius: 18)
                    .blendMode(.plusLighter)
                    .opacity(isPlaying ? 0.74 : 0)

                    RadialGradient(
                        colors: [
                            song.magicColor.opacity(isPlaying ? 0.24 : 0),
                            .white.opacity(isPlaying ? 0.10 : 0),
                            .clear
                        ],
                        center: UnitPoint(x: counterCenterX, y: counterCenterY),
                        startRadius: 2,
                        endRadius: width * 0.38
                    )
                    .frame(width: width, height: height * 0.80)
                    .offset(y: height * 0.24)
                    .blur(radius: 15)
                    .blendMode(.plusLighter)
                    .opacity(isPlaying ? 0.62 : 0)

                    RadialGradient(
                        colors: [
                            .white.opacity(isPlaying ? 0.19 : 0),
                            song.magicColor.opacity(isPlaying ? 0.27 : 0),
                            .clear
                        ],
                        center: UnitPoint(x: glowCenterX, y: glowCenterY),
                        startRadius: 0,
                        endRadius: width * 0.30
                    )
                    .frame(width: width, height: height * 0.86)
                    .offset(y: height * 0.30)
                    .blur(radius: 8)
                    .blendMode(.plusLighter)
                    .opacity(isPlaying ? 0.66 : 0)
                }
                .frame(width: width, height: height)
                .animation(.easeOut(duration: 0.24), value: isPlaying)
            }
        }
    }

    private func currentPlaybackTime(fallbackTime: TimeInterval) -> TimeInterval {
        guard isPlaying else { return 0 }
        let playbackTime = MPMusicPlayerController.applicationMusicPlayer.currentPlaybackTime
        return playbackTime > 0 ? playbackTime : fallbackTime
    }

    private func playbackBPM(for song: DemoSong) -> Double {
        let libraryBPM = song.mediaItem?.beatsPerMinute ?? 0
        if libraryBPM > 0 {
            return min(156, max(58, Double(libraryBPM)))
        }
        return estimatedBPM(for: song)
    }

    private func randomUnit(index: Int, salt: Double) -> Double {
        let seed = (Double(index) + 1.0) * 12.9898 + Double(song.id) * 0.071 + salt * 78.233
        let value = sin(seed) * 43758.5453
        return value - floor(value)
    }

    private func randomPhase(index: Int, salt: Double) -> Double {
        randomUnit(index: index, salt: salt) * .pi * 2
    }

    private func positiveModulo(_ value: Double, _ divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }

    private func loopEnvelope(progress: Double) -> Double {
        let fadeIn = smoothstep(edge0: 0.00, edge1: 0.08, x: progress)
        let fadeOut = 1 - smoothstep(edge0: 0.72, edge1: 0.92, x: progress)
        return max(0, min(fadeIn, fadeOut))
    }

    private func loopSpinAngle(progress: Double, phase: Double) -> Double {
        let normalizedProgress = min(max(progress / 0.92, 0), 1)
        return normalizedProgress * .pi * 2 + phase
    }

    private func smoothstep(edge0: Double, edge1: Double, x: Double) -> Double {
        let progress = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return progress * progress * (3 - 2 * progress)
    }

    private func estimatedBPM(for song: DemoSong) -> Double {
        let energy = min(1, max(0, song.rhythmEnergy))
        return 54 + energy * 68
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
        GeometryReader { proxy in
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
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .opacity(isLoading ? 0 : 1)
                .scaleEffect(isLoading ? 0.98 : 1, anchor: .leading)

                Text("歌曲加载中")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .opacity(isLoading ? 1 : 0)
                .scaleEffect(isLoading ? 1 : 0.98, anchor: .center)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: 53, alignment: .center)
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
                self.glassEffect(.regular.tint(.black.opacity(0.24)).interactive(), in: .rect(cornerRadius: cornerRadius))
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
    static func search(term: String, country: String = "us", limit: Int) async throws -> [ITunesTrack] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components?.url else { return [] }

        let request = URLRequest(url: url, timeoutInterval: 5)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        return response.results
    }

    static func artworkImage(from urlString: String?) async -> UIImage? {
        guard let urlString,
              let url = URL(string: urlString.replacingOccurrences(of: "100x100bb", with: "600x600bb")) else {
            return nil
        }

        do {
            let request = URLRequest(url: url, timeoutInterval: 5)
            let (data, _) = try await URLSession.shared.data(for: request)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

private enum AppleMusicRSSClient {
    static func topSongs(storefront: String = "us", limit: Int) async throws -> [ITunesTrack] {
        let safeLimit = min(max(limit, 10), 50)
        let urlString = "https://rss.marketingtools.apple.com/api/v2/\(storefront)/music/most-played/\(safeLimit)/songs.json"
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
    let previewURL: String?
    let releaseDate: Date?
    let primaryGenreName: String?

    private enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case id
        case trackName
        case name
        case artistName
        case artworkURL100 = "artworkUrl100"
        case previewURL = "previewUrl"
        case releaseDate
        case primaryGenreName
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
        previewURL = try container.decodeIfPresent(String.self, forKey: .previewURL)
        primaryGenreName = try container.decodeIfPresent(String.self, forKey: .primaryGenreName)
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
        return id.isEmpty || id == "0" ? nil : id
    }
}

private struct DemoSong: Identifiable, Equatable {
    let id: Int
    let title: String
    let artist: String
    let colors: [Color]
    let mediaItem: MPMediaItem?
    let storeID: String?
    let previewURL: String?
    let spotifyURI: String?
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
        previewURL: String? = nil,
        spotifyURI: String? = nil,
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
        self.previewURL = previewURL
        self.spotifyURI = spotifyURI
        self.artworkImage = artworkImage
        self.backdropImage = backdropImage
        self.lyricsText = lyricsText
        self.magicColor = magicColor ?? colors.first ?? .black
        self.source = source
    }

    var isPlayable: Bool {
        hasApplePlaybackSource || previewURL != nil
    }

    var isHomeSurfacePlayable: Bool {
        mediaItem != nil || previewURL != nil
    }

    static func == (lhs: DemoSong, rhs: DemoSong) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.storeID == rhs.storeID &&
        lhs.previewURL == rhs.previewURL &&
        lhs.spotifyURI == rhs.spotifyURI &&
        lhs.source == rhs.source &&
        (lhs.artworkImage != nil) == (rhs.artworkImage != nil) &&
        (lhs.backdropImage != nil) == (rhs.backdropImage != nil)
    }

    var hasApplePlaybackSource: Bool {
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

private enum DemoSongSource: Hashable {
    case demo
    case library
    case recommendation
    case spotify
    case placeholder

    var isRealDiscoverySource: Bool {
        switch self {
        case .library, .recommendation, .spotify:
            return true
        case .demo, .placeholder:
            return false
        }
    }

    var rotationPriority: Int {
        switch self {
        case .spotify: return 0
        case .recommendation: return 1
        case .library: return 2
        case .demo: return 3
        case .placeholder: return 4
        }
    }
}

private struct HomeInteractiveSongSquare: View {
    let frontSong: DemoSong
    let backSong: DemoSong
    let displayedSong: DemoSong
    let isPlaying: Bool
    let gravity: HomeCoverGravity
    let isFlipping: Bool
    let isAppearing: Bool
    let flipGeneration: UUID
    let variation: HomeFlipVariation
    let onTap: () -> Void
    let onDislike: () -> Void

    var body: some View {
        GeometryReader { _ in
            HomeFlipSongSquare(
                frontSong: frontSong,
                backSong: backSong,
                isPlaying: isPlaying,
                isFlipping: isFlipping,
                isAppearing: isAppearing,
                flipGeneration: flipGeneration,
                variation: variation
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(perform: onTap)
            .contextMenu {
                Button(role: .destructive, action: onDislike) {
                    Label("不推荐这首", systemImage: "hand.thumbsdown")
                }
            }
            .scaleEffect(gravity.scale)
            .offset(gravity.offset)
            .shadow(
                color: displayedSong.magicColor.opacity(isPlaying ? 0.36 : Double(max(0, gravity.glow - 0.55)) * 0.20),
                radius: isPlaying ? 18 : 8,
                y: isPlaying ? 8 : 3
            )
            .animation(.smooth(duration: 0.34, extraBounce: 0.0), value: isPlaying)
            .animation(.smooth(duration: 0.42, extraBounce: 0.0), value: gravity.glow)
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

                if let artworkImage = PlayerArtworkWarmupCache.shared.artwork(for: song) ?? song.artworkImage {
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
                if isPlaying {
                    ZStack(alignment: .bottomLeading) {
                        RadialGradient(
                            colors: [
                                song.magicColor.opacity(0.42),
                                song.magicColor.opacity(0.16),
                                .clear
                            ],
                            center: .bottomLeading,
                            startRadius: 0,
                            endRadius: side * 0.86
                        )
                        .blendMode(.screen)

                        LinearGradient(
                            colors: [
                                .clear,
                                .black.opacity(0.24)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .overlay {
                if song.isPlaceholder {
                    PlaceholderCardLoadingSweep(seed: song.id)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        song.source == .spotify
                            ? Color(red: 0.1, green: 0.86, blue: 0.36).opacity(0.92)
                            : .white.opacity(0.08),
                        lineWidth: song.source == .spotify ? 2 : 1
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                if song.source == .spotify {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .black))
                        Text("SPOTIFY")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.black.opacity(0.86))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color(red: 0.1, green: 0.86, blue: 0.36), in: Capsule())
                    .shadow(color: Color(red: 0.1, green: 0.86, blue: 0.36).opacity(0.42), radius: 9, y: 3)
                    .padding(7)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isPlaying {
                    HStack(spacing: 2.5) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(.white.opacity(0.78))
                                .frame(width: 2.5, height: CGFloat([8, 13, 6][index]))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.30))
                    .clipShape(Capsule())
                    .padding(7)
                    .shadow(color: song.magicColor.opacity(0.28), radius: 8, y: 3)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomLeading)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct PlaceholderCardLoadingSweep: View {
    let seed: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let phaseSeed = Double(abs(seed % 23)) * 0.037
            let phase = positiveModulo(timeline.date.timeIntervalSinceReferenceDate * 0.30 + phaseSeed, 1)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)

                ZStack {
                    RadialGradient(
                        colors: [
                            .white.opacity(0.06),
                            .white.opacity(0.018),
                            .clear
                        ],
                        center: UnitPoint(
                            x: 0.28 + CGFloat(phase) * 0.44,
                            y: 0.18 + CGFloat(sin(phase * .pi * 2)) * 0.10
                        ),
                        startRadius: 0,
                        endRadius: width * 0.72
                    )
                    .blendMode(.screen)

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.05),
                                    .white.opacity(0.20),
                                    .white.opacity(0.07),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: width * 0.34, height: height * 1.65)
                        .rotationEffect(.degrees(18))
                        .blur(radius: 8)
                        .offset(
                            x: -width * 0.76 + width * 1.52 * CGFloat(phase),
                            y: -height * 0.32
                        )
                        .blendMode(.plusLighter)

                    LinearGradient(
                        colors: [
                            .white.opacity(0.030),
                            .clear,
                            .black.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)
                }
                .frame(width: width, height: height)
            }
        }
        .allowsHitTesting(false)
        .opacity(0.88)
    }

    private func positiveModulo(_ value: Double, _ divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private struct HomeFlipSongSquare: View {
    let frontSong: DemoSong
    let backSong: DemoSong
    let isPlaying: Bool
    let isFlipping: Bool
    let isAppearing: Bool
    let flipGeneration: UUID
    let variation: HomeFlipVariation
    @State private var progress: CGFloat = 0

    var body: some View {
        cardBody
        .rotation3DEffect(
            .degrees(isAppearing ? 0 : flipRotation),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: 0.72
        )
        .rotationEffect(.degrees(variation.tilt * sin(Double(progress) * .pi)))
        .offset(y: variation.lift * sin(CGFloat(progress) * .pi))
        .task(id: flipGeneration) {
            await runFlipIfNeeded()
        }
        .onChange(of: isFlipping) { _, newValue in
            if newValue == false {
                progress = 0
            }
        }
    }

    private var flipRotation: Double {
        Double(progress * 180)
    }

    @ViewBuilder
    private var cardBody: some View {
        if isAppearing {
            SongSquare(song: backSong, isPlaying: isPlaying)
                .opacity(Double(progress))
                .scaleEffect(0.975 + progress * 0.025)
                .rotation3DEffect(
                    .degrees(-72 + Double(progress) * 72),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    perspective: 0.72
                )
        } else {
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
        }
    }

    @MainActor
    private func runFlipIfNeeded() async {
        guard isFlipping else {
            progress = 0
            return
        }
        progress = 0
        let delayMs = max(0, Int((variation.delay * 1000).rounded()))
        if delayMs > 0 {
            try? await Task.sleep(for: .milliseconds(delayMs))
        }
        guard Task.isCancelled == false else { return }
        let duration = Double(variation.durationScale) * (isAppearing ? 0.62 : 0.54)
        let animation: Animation = isAppearing
            ? .smooth(duration: duration, extraBounce: 0.0)
            : .interactiveSpring(response: duration, dampingFraction: 0.88, blendDuration: 0.02)
        withAnimation(animation) {
            progress = 1
        }
    }
}

#Preview {
    ContentView()
}
