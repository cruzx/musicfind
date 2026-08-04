import Foundation

struct PlaybackCoreState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case starting
        case playing
        case paused
        case backgroundPlaying
        case backgroundPaused
    }

    enum ForegroundDirective: Equatable, Sendable {
        case synchronizeOnly
        case adoptObservedSong
    }

    private(set) var requestID = 0
    private(set) var selectedSongID: Int?
    private(set) var retainedProgress: TimeInterval = 0
    private(set) var phase: Phase = .idle

    mutating func select(songID: Int) -> Int {
        requestID &+= 1
        selectedSongID = songID
        retainedProgress = 0
        phase = .starting
        return requestID
    }

    mutating func didStart(songID: Int) {
        guard selectedSongID == songID else { return }
        retainedProgress = 0
        phase = .playing
    }

    mutating func pause(songID: Int, progress: TimeInterval) {
        selectedSongID = songID
        retainedProgress = sanitized(progress)
        phase = .paused
    }

    @discardableResult
    mutating func resume(songID: Int) -> TimeInterval {
        if selectedSongID != songID {
            selectedSongID = songID
            retainedProgress = 0
        }
        phase = .playing
        return retainedProgress
    }

    mutating func enterBackground(songID: Int?, progress: TimeInterval, isPlaying: Bool) {
        if let songID {
            selectedSongID = songID
        }
        retainedProgress = sanitized(progress)
        phase = isPlaying ? .backgroundPlaying : .backgroundPaused
    }

    mutating func returnToForeground(
        observedSongID: Int?,
        progress: TimeInterval,
        isPlaying: Bool
    ) -> ForegroundDirective {
        let directive: ForegroundDirective
        if let observedSongID, let selectedSongID, observedSongID != selectedSongID {
            self.selectedSongID = observedSongID
            directive = .adoptObservedSong
        } else {
            if let observedSongID {
                selectedSongID = observedSongID
            }
            directive = .synchronizeOnly
        }
        retainedProgress = sanitized(progress)
        phase = isPlaying ? .playing : .paused
        return directive
    }

    private func sanitized(_ progress: TimeInterval) -> TimeInterval {
        guard progress.isFinite else { return 0 }
        return max(0, progress)
    }
}
