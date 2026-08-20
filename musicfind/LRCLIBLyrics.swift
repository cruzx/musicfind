import Foundation

nonisolated struct SyncedLyricLine: Identifiable, Equatable, Sendable {
    let timestamp: TimeInterval
    let text: String

    var id: String {
        "\(timestamp)-\(text)"
    }
}

nonisolated struct LRCLIBLyricsQuery: Hashable, Sendable {
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Int?

    init(trackName: String, artistName: String, albumName: String?, duration: TimeInterval?) {
        self.trackName = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artistName = artistName.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedAlbum = albumName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.albumName = trimmedAlbum?.isEmpty == false ? trimmedAlbum : nil

        if let duration, duration.isFinite, duration > 0 {
            self.duration = Int(duration.rounded())
        } else {
            self.duration = nil
        }
    }
}

actor LRCLIBLyricsService {
    static let shared = LRCLIBLyricsService()

    private struct Response: Decodable {
        let instrumental: Bool
        let syncedLyrics: String?
    }

    private var cache: [LRCLIBLyricsQuery: [SyncedLyricLine]] = [:]
    private var missingQueries: [LRCLIBLyricsQuery: Date] = [:]
    private var activeTasks: [LRCLIBLyricsQuery: Task<[SyncedLyricLine]?, Never>] = [:]

    func lyrics(for query: LRCLIBLyricsQuery) async -> [SyncedLyricLine]? {
        guard query.trackName.isEmpty == false, query.artistName.isEmpty == false else {
            return nil
        }
        if let cached = cache[query] {
            return cached
        }
        if let missingDate = missingQueries[query] {
            if Date().timeIntervalSince(missingDate) < 20 {
                return nil
            }
            missingQueries[query] = nil
        }
        if let activeTask = activeTasks[query] {
            return await activeTask.value
        }

        let task = Task<[SyncedLyricLine]?, Never> {
            await Self.fetch(query: query)
        }
        activeTasks[query] = task
        let result = await task.value
        activeTasks[query] = nil

        if let result, result.isEmpty == false {
            cache[query] = result
        } else {
            missingQueries[query] = Date()
        }
        return result
    }

    private static func fetch(query: LRCLIBLyricsQuery) async -> [SyncedLyricLine]? {
        if let detailedResult = await fetch(query: query, includeDetails: true) {
            return detailedResult
        }

        if query.albumName != nil || query.duration != nil,
           let basicResult = await fetch(query: query, includeDetails: false) {
            return basicResult
        }
        return await search(query: query)
    }

    private static func fetch(
        query: LRCLIBLyricsQuery,
        includeDetails: Bool
    ) async -> [SyncedLyricLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: query.trackName),
            URLQueryItem(name: "artist_name", value: query.artistName)
        ]
        if includeDetails, let albumName = query.albumName {
            items.append(URLQueryItem(name: "album_name", value: albumName))
        }
        if includeDetails, let duration = query.duration {
            items.append(URLQueryItem(name: "duration", value: String(duration)))
        }
        components?.queryItems = items

        guard let url = components?.url else { return nil }
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 8
        )
        request.setValue(
            "FlipMusic/1.0 (https://github.com/cruzx/musicfind)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            let payload = try JSONDecoder().decode(Response.self, from: data)
            guard payload.instrumental == false,
                  let syncedLyrics = payload.syncedLyrics else {
                return nil
            }
            let lines = LRCLIBLRCParser.parse(syncedLyrics)
            return lines.isEmpty ? nil : lines
        } catch {
            return nil
        }
    }

    private static func search(query: LRCLIBLyricsQuery) async -> [SyncedLyricLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: query.trackName),
            URLQueryItem(name: "artist_name", value: query.artistName)
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 8
        )
        request.setValue(
            "FlipMusic/1.0 (https://github.com/cruzx/musicfind)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return nil }
            let matches = try JSONDecoder().decode([Response].self, from: data)
            for match in matches where match.instrumental == false {
                guard let syncedLyrics = match.syncedLyrics else { continue }
                let lines = LRCLIBLRCParser.parse(syncedLyrics)
                if lines.isEmpty == false { return lines }
            }
            return nil
        } catch {
            return nil
        }
    }
}

nonisolated enum LRCLIBLRCParser {
    private static let timestampPattern = #"\[(\d{1,3}):(\d{2}(?:\.\d{1,3})?)\]"#

    static func parse(_ source: String) -> [SyncedLyricLine] {
        guard let expression = try? NSRegularExpression(pattern: timestampPattern) else {
            return []
        }

        var parsed: [SyncedLyricLine] = []
        for rawLine in source.components(separatedBy: .newlines) {
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            let matches = expression.matches(in: rawLine, range: range)
            guard matches.isEmpty == false else { continue }

            let lyricStart = matches.compactMap { Range($0.range, in: rawLine)?.upperBound }.max()
            guard let lyricStart else { continue }
            let text = String(rawLine[lyricStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { continue }

            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: rawLine),
                      let secondRange = Range(match.range(at: 2), in: rawLine),
                      let minutes = Double(rawLine[minuteRange]),
                      let seconds = Double(rawLine[secondRange]) else {
                    continue
                }
                parsed.append(
                    SyncedLyricLine(
                        timestamp: minutes * 60 + seconds,
                        text: text
                    )
                )
            }
        }

        return parsed
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.text < rhs.text
                }
                return lhs.timestamp < rhs.timestamp
            }
            .reduce(into: []) { result, line in
                guard result.last?.timestamp != line.timestamp || result.last?.text != line.text else {
                    return
                }
                result.append(line)
            }
    }
}
