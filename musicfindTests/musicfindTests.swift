//
//  musicfindTests.swift
//  musicfindTests
//
//  Created by 项程锦 on 2026/6/30.
//

import Foundation
import Testing
@testable import musicfind

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
