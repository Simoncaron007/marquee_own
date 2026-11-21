import Foundation

enum MediaKind: String, Codable, Sendable {
    case movie, show
}

/// One episode file on disk.
struct EpisodeFile: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let season: Int
    let episode: Int
}

/// A movie or a show as found on disk (several season folders of one show are merged into one item).
struct LibraryItem: Identifiable, Hashable, Sendable {
    let id: String
    let kind: MediaKind
    var title: String
    var year: Int?
    var dateAdded: Date
    var movieFile: URL?
    var episodes: [EpisodeFile]
    var folders: [URL]

    var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }
}

// MARK: - Metadata (stored, converted from TMDB)

struct Person: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var role: String
    var profilePath: String?
    var uid: String { "\(id)-\(role)" }
}

struct MediaMetadata: Codable, Hashable {
    var tmdbID: Int
    var kind: MediaKind
    var title: String
    var originalTitle: String?
    var overview: String
    var tagline: String?
    var year: Int?
    var endYear: Int?
    var runtime: Int?
    var genres: [String]
    var posterPath: String?
    var backdropPath: String?
    var rating: Double?
    var cast: [Person]
    var crew: [Person]
    var network: String?
    var status: String?
    var seasonCount: Int?
}

struct EpisodeMeta: Codable, Hashable {
    var season: Int
    var episode: Int
    var name: String?
    var overview: String?
    var stillPath: String?
    var airDate: String?
    var runtime: Int?
}

struct WatchRecord: Codable, Hashable {
    var watched = false
    var watchedDate: Date?
    var lastPlayed: Date?
    var playCount = 0
}

/// Everything persisted to ~/Library/Application Support/Marquee/library.json
struct PersistedState: Codable {
    var matches: [String: Int] = [:]          // item id → TMDB id
    var lockedMatches: Set<String> = []        // matches chosen by hand
    var unmatchable: Set<String> = []          // searched, found nothing
    var movieMeta: [Int: MediaMetadata] = [:]
    var showMeta: [Int: MediaMetadata] = [:]
    var seasonMeta: [String: [EpisodeMeta]] = [:]  // "tmdbID:season"
    var watch: [String: WatchRecord] = [:]
}

struct HistoryEntry: Identifiable {
    let id: String
    let item: LibraryItem
    let episode: EpisodeFile?
    let date: Date
    let watched: Bool
}

enum SortKey: String, CaseIterable {
    case title = "Title", added = "Date Added", year = "Year", rating = "Rating"
}

enum WatchFilter: String, CaseIterable {
    case all = "All", unwatched = "Unwatched", watched = "Watched"
}

struct MetadataLanguage: Hashable {
    let code: String
    let name: String
}

enum AppPaths {
    static let support: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marquee", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let images: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marquee/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var stateFile: URL { support.appendingPathComponent("library.json") }
}

func formatRuntime(_ minutes: Int) -> String {
    minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
}
