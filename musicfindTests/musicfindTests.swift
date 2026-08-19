//
//  musicfindTests.swift
//  musicfindTests
//
//  Created by 项程锦 on 2026/6/30.
//

import Foundation
import Testing
@testable import musicfind

struct LRCLIBLRCParserTests {
    @Test("Parses synced lyrics and orders them by timestamp")
    func parsesAndSortsLines() {
        let source = """
        [00:12.50]Second line
        [00:03.20]First line
        [ar:Example Artist]
        """

        let lines = LRCLIBLRCParser.parse(source)

        #expect(lines.count == 2)
        #expect(lines[0].text == "First line")
        #expect(lines[0].timestamp == 3.2)
        #expect(lines[1].text == "Second line")
        #expect(lines[1].timestamp == 12.5)
    }

    @Test("Creates one lyric entry for every timestamp on a shared line")
    func parsesMultipleTimestamps() {
        let source = "[00:05.00][00:45.250]Repeated chorus"

        let lines = LRCLIBLRCParser.parse(source)

        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.text == "Repeated chorus" })
        #expect(lines.map(\.timestamp) == [5, 45.25])
    }
}

@MainActor
struct PlaybackCoreStateTests {
    @Test("Clicking a song creates a fresh start-at-zero request")
    func clickStartsSelectedSongAtBeginning() {
        var state = PlaybackCoreState()

        let requestID = state.select(songID: 101)

        #expect(requestID == 1)
        #expect(state.selectedSongID == 101)
        #expect(state.retainedProgress == 0)
        #expect(state.phase == .starting)
    }

    @Test("Pause and resume retain the current position")
    func pauseAndResumeRetainProgress() {
        var state = PlaybackCoreState()
        state.select(songID: 101)
        state.didStart(songID: 101)

        state.pause(songID: 101, progress: 42.75)
        let resumePosition = state.resume(songID: 101)

        #expect(resumePosition == 42.75)
        #expect(state.retainedProgress == 42.75)
        #expect(state.phase == .playing)
    }

    @Test("Switching songs invalidates the old request and starts the new song at zero")
    func switchingSongsCreatesNewRequest() {
        var state = PlaybackCoreState()
        let firstRequest = state.select(songID: 101)
        state.didStart(songID: 101)
        state.pause(songID: 101, progress: 86)

        let secondRequest = state.select(songID: 202)

        #expect(secondRequest > firstRequest)
        #expect(state.selectedSongID == 202)
        #expect(state.retainedProgress == 0)
        #expect(state.phase == .starting)
    }

    @Test("Returning from background keeps the same song and observed progress")
    func backgroundRecoveryDoesNotReloadCurrentSong() {
        var state = PlaybackCoreState()
        state.select(songID: 101)
        state.didStart(songID: 101)
        state.enterBackground(songID: 101, progress: 63.5, isPlaying: true)

        let directive = state.returnToForeground(
            observedSongID: 101,
            progress: 71.25,
            isPlaying: true
        )

        #expect(directive == .synchronizeOnly)
        #expect(state.selectedSongID == 101)
        #expect(state.retainedProgress == 71.25)
        #expect(state.phase == .playing)
    }

    @Test("Foreground synchronization adopts a system-side song change without restarting it")
    func foregroundAdoptsSystemSongChange() {
        var state = PlaybackCoreState()
        state.select(songID: 101)
        state.enterBackground(songID: 101, progress: 20, isPlaying: true)

        let directive = state.returnToForeground(
            observedSongID: 202,
            progress: 8,
            isPlaying: true
        )

        #expect(directive == .adoptObservedSong)
        #expect(state.selectedSongID == 202)
        #expect(state.retainedProgress == 8)
        #expect(state.phase == .playing)
    }
}

struct PlaylistCuratorTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Curator returns the requested number without duplicate songs")
    func requestedCountAndDeduplication() {
        let tracks = (0..<40).map { index in
            seed(id: index, artist: "Artist \(index % 10)", playCount: 40 - index, energy: Double(index % 10) / 10)
        } + [seed(id: 100, title: "Song 0", artist: "Artist 0", playCount: 999, energy: 0.5)]

        let result = PlaylistCurator.curate(tracks, requestedCount: 25, referenceDate: referenceDate)

        #expect(result.tracks.count == 25)
        #expect(Set(result.tracks.map(\.id)).count == 25)
        #expect(result.sections.count == 4)
    }

    @Test("Curator keeps one artist from dominating when alternatives exist")
    func artistDiversity() {
        let dominant = (0..<20).map {
            seed(id: $0, artist: "Same Artist", playCount: 200 - $0, energy: 0.6)
        }
        let alternatives = (20..<55).map {
            seed(id: $0, artist: "Artist \($0)", playCount: 30, energy: Double($0 % 10) / 10)
        }

        let result = PlaylistCurator.curate(dominant + alternatives, requestedCount: 25, referenceDate: referenceDate)
        let dominantCount = result.tracks.filter { $0.artist == "Same Artist" }.count

        #expect(dominantCount <= 2)
    }

    @Test("The lift section is more energetic than the deep section")
    func fourActEnergyShape() {
        let tracks = (0..<60).map { index in
            seed(id: index, artist: "Artist \(index)", playCount: 20, energy: Double(index) / 59)
        }

        let result = PlaylistCurator.curate(tracks, requestedCount: 50, referenceDate: referenceDate)
        let lift = result.sections.first { $0.kind == .lift }?.tracks ?? []
        let deep = result.sections.first { $0.kind == .deep }?.tracks ?? []
        let liftAverage = lift.map(\.energy).reduce(0, +) / Double(lift.count)
        let deepAverage = deep.map(\.energy).reduce(0, +) / Double(deep.count)

        #expect(liftAverage > deepAverage)
    }

    @Test("Frequently and recently played songs are preferred")
    func playbackPreference() {
        let favorites = (0..<8).map {
            PlaylistSeedTrack(
                id: $0,
                title: "Favorite \($0)",
                artist: "Favorite Artist \($0)",
                playCount: 80,
                lastPlayedDate: referenceDate.addingTimeInterval(-Double($0) * 3_600),
                energy: 0.5
            )
        }
        let unplayed = (8..<50).map {
            seed(id: $0, artist: "Other Artist \($0)", playCount: 0, energy: 0.5)
        }

        let result = PlaylistCurator.curate(favorites + unplayed, requestedCount: 25, referenceDate: referenceDate)

        #expect(Set(favorites.map(\.id)).isSubset(of: Set(result.tracks.map(\.id))))
    }

    private func seed(
        id: Int,
        title: String? = nil,
        artist: String,
        playCount: Int,
        energy: Double
    ) -> PlaylistSeedTrack {
        PlaylistSeedTrack(
            id: id,
            title: title ?? "Song \(id)",
            artist: artist,
            playCount: playCount,
            lastPlayedDate: nil,
            energy: energy
        )
    }
}
