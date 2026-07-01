import Foundation
import SwiftData

@Model
final class Track {
    var title: String
    var artistName: String
    var albumName: String?

    var platform: Platform
    var platformID: String?

    // Persist URL as a raw string to avoid model migration issues; expose computed URL.
    private var artworkURLString: String?
    var artworkURL: URL? {
        get { artworkURLString.flatMap { URL(string: $0) } }
        set { artworkURLString = newValue?.absoluteString }
    }

    var dateAdded: Date

    init(title: String,
         artistName: String,
         albumName: String? = nil,
         platform: Platform,
         platformID: String? = nil,
         artworkURL: URL? = nil,
         dateAdded: Date = .now) {
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.platform = platform
        self.platformID = platformID
        self.artworkURLString = artworkURL?.absoluteString
        self.dateAdded = dateAdded
    }
}

// Use a RawRepresentable enum to ensure stable persistence
enum Platform: Int, Codable, CaseIterable {
    case appleMusic = 0
    case spotify = 1
}
