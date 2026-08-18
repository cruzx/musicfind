import Foundation

struct PlaylistSeedTrack: Identifiable, Equatable {
    let id: Int
    let title: String
    let artist: String
    let playCount: Int
    let lastPlayedDate: Date?
    let energy: Double
}

struct CuratedPlaylistSection: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case opening
        case lift
        case deep
        case resolve

        var title: String {
            switch self {
            case .opening: "轻盈开场"
            case .lift: "节奏升温"
            case .deep: "情绪深夜"
            case .resolve: "安静收尾"
            }
        }

        var targetEnergy: Double {
            switch self {
            case .opening: 0.46
            case .lift: 0.82
            case .deep: 0.24
            case .resolve: 0.52
            }
        }
    }

    let kind: Kind
    let tracks: [PlaylistSeedTrack]

    var id: String { kind.rawValue }
}

struct CuratedPlaylistDraft: Equatable {
    let title: String
    let sections: [CuratedPlaylistSection]

    var tracks: [PlaylistSeedTrack] {
        sections.flatMap(\.tracks)
    }
}

enum PlaylistCurator {
    static let supportedCounts = [25, 50, 100]

    static func curate(
        _ input: [PlaylistSeedTrack],
        requestedCount: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> CuratedPlaylistDraft {
        let uniqueTracks = unique(input)
        let targetCount = min(max(1, requestedCount), uniqueTracks.count)
        let artistLimit = max(2, targetCount / 12)
        let ranked = uniqueTracks.sorted {
            preferenceScore($0, referenceDate: referenceDate) > preferenceScore($1, referenceDate: referenceDate)
        }
        let selected = diversifiedSelection(ranked, count: targetCount, artistLimit: artistLimit)
        let sectionCounts = balancedSectionCounts(total: selected.count)
        var remaining = selected
        var sections: [CuratedPlaylistSection] = []

        for (index, kind) in CuratedPlaylistSection.Kind.allCases.enumerated() {
            let count = sectionCounts[index]
            let ordered = remaining.sorted { lhs, rhs in
                sectionFit(lhs, kind: kind, referenceDate: referenceDate) >
                    sectionFit(rhs, kind: kind, referenceDate: referenceDate)
            }
            let tracks = Array(ordered.prefix(count))
            let trackIDs = Set(tracks.map(\.id))
            remaining.removeAll { trackIDs.contains($0.id) }
            sections.append(CuratedPlaylistSection(kind: kind, tracks: tracks))
        }

        return CuratedPlaylistDraft(
            title: playlistTitle(referenceDate: referenceDate, calendar: calendar),
            sections: sections.filter { $0.tracks.isEmpty == false }
        )
    }

    private static func unique(_ input: [PlaylistSeedTrack]) -> [PlaylistSeedTrack] {
        var seenIDs = Set<Int>()
        var seenKeys = Set<String>()
        return input.filter { track in
            if seenIDs.insert(track.id).inserted == false { return false }
            let key = "\(normalize(track.title))|\(normalize(track.artist))"
            return seenKeys.insert(key).inserted
        }
    }

    private static func diversifiedSelection(
        _ ranked: [PlaylistSeedTrack],
        count: Int,
        artistLimit: Int
    ) -> [PlaylistSeedTrack] {
        var result: [PlaylistSeedTrack] = []
        var artistCounts: [String: Int] = [:]

        for track in ranked where result.count < count {
            let artist = normalize(track.artist)
            guard artistCounts[artist, default: 0] < artistLimit else { continue }
            result.append(track)
            artistCounts[artist, default: 0] += 1
        }

        if result.count < count {
            let selectedIDs = Set(result.map(\.id))
            result.append(contentsOf: ranked.filter { selectedIDs.contains($0.id) == false }.prefix(count - result.count))
        }
        return result
    }

    private static func preferenceScore(_ track: PlaylistSeedTrack, referenceDate: Date) -> Double {
        let playScore = log2(Double(max(0, track.playCount)) + 1) * 18
        let recencyScore: Double
        if let lastPlayedDate = track.lastPlayedDate {
            let daysAgo = max(0, referenceDate.timeIntervalSince(lastPlayedDate) / 86_400)
            recencyScore = max(0, 90 - daysAgo) * 0.55
        } else {
            recencyScore = 0
        }
        return playScore + recencyScore + stableTieBreak(track)
    }

    private static func sectionFit(
        _ track: PlaylistSeedTrack,
        kind: CuratedPlaylistSection.Kind,
        referenceDate: Date
    ) -> Double {
        let energyFit = 1 - abs(min(1, max(0, track.energy)) - kind.targetEnergy)
        return energyFit * 100 + preferenceScore(track, referenceDate: referenceDate) * 0.18
    }

    private static func balancedSectionCounts(total: Int) -> [Int] {
        let base = total / 4
        let remainder = total % 4
        return (0..<4).map { base + ($0 < remainder ? 1 : 0) }
    }

    private static func playlistTitle(referenceDate: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: referenceDate) {
        case 5..<11: "晨光拾音"
        case 11..<18: "午后脉冲"
        case 18..<23: "夜色回声"
        default: "午夜心事"
        }
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(scalars)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableTieBreak(_ track: PlaylistSeedTrack) -> Double {
        let scalars = "\(track.title)|\(track.artist)".unicodeScalars
        let value = scalars.reduce(0) { (($0 &* 31) &+ Int($1.value)) % 997 }
        return Double(value) / 997
    }
}
