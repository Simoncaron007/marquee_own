import Foundation

/// Walks the library folder and turns files/folders into movies and shows.
///
/// Works with a flat "downloads" folder, and gets more reliable if you add
/// optional `Movies/` and `TV Shows/` subfolders (their contents are then
/// taken to be movies or shows without guessing).
enum LibraryScanner {
    static let movieFolderNames: Set<String> = ["movies", "movie", "films", "film"]
    static let showFolderNames: Set<String> = ["tv", "tv shows", "tvshows", "tv series", "series", "shows", "séries"]
    static let ignoredFolderNames: Set<String> = [
        "sample", "samples", "extras", "extra", "featurettes", "behind the scenes", "bonus",
        "trailers", "deleted scenes", "interviews", "subs", "subtitles", "other", "shorts"
    ]

    static func scan(root: URL) -> [LibraryItem] {
        var found: [LibraryItem] = []
        for entry in children(of: root) {
            let name = entry.lastPathComponent.lowercased()
            if isDirectory(entry), movieFolderNames.contains(name) {
                found += children(of: entry).compactMap { item(for: $0, hint: .movie) }
            } else if isDirectory(entry), showFolderNames.contains(name) {
                found += children(of: entry).compactMap { item(for: $0, hint: .show) }
            } else if let newItem = item(for: entry, hint: nil) {
                found.append(newItem)
            }
        }
        return merge(found)
    }

    // MARK: - Items

    private static func item(for url: URL, hint: MediaKind?) -> LibraryItem? {
        let added = dateAdded(url)

        if !isDirectory(url) {
            guard FilenameParser.isVideo(url), !FilenameParser.isSample(url) else { return nil }
            let p = FilenameParser.parse(url.deletingPathExtension().lastPathComponent)
            guard !p.title.isEmpty else { return nil }
            if hint != .movie, let s = p.season, let e = p.episode {
                return makeShow(title: p.title, year: p.year, added: added,
                                episodes: [EpisodeFile(url: url, season: s, episode: e)],
                                folders: [url.deletingLastPathComponent()])
            }
            if hint == .show { return nil }
            return makeMovie(title: p.title, year: p.year, added: added, file: url, folder: url.deletingLastPathComponent())
        }

        let videos = videoFiles(in: url)
        guard !videos.isEmpty else { return nil }
        let p = FilenameParser.parse(url.lastPathComponent)

        let strictEpisodes = videos.filter {
            let vp = FilenameParser.parse($0.deletingPathExtension().lastPathComponent)
            return vp.season != nil && vp.episode != nil
        }
        let isShow: Bool
        switch hint {
        case .movie: isShow = false
        case .show: isShow = true
        case nil: isShow = p.season != nil || strictEpisodes.count >= 2
        }

        if isShow {
            let episodes = videos.compactMap { episodeFile($0, showFolder: url, folderSeason: p.season) }
            guard !episodes.isEmpty else { return nil }
            var title = p.title
            if title.isEmpty, let first = episodes.first {
                title = FilenameParser.parse(first.url.deletingPathExtension().lastPathComponent).title
            }
            guard !title.isEmpty else { return nil }
            return makeShow(title: title, year: p.year, added: added, episodes: episodes, folders: [url])
        }

        let main = videos.max { fileSize($0) < fileSize($1) }!
        var title = p.title
        var year = p.year
        if title.isEmpty {
            let fp = FilenameParser.parse(main.deletingPathExtension().lastPathComponent)
            title = fp.title
            year = year ?? fp.year
        }
        guard !title.isEmpty else { return nil }
        return makeMovie(title: title, year: year, added: added, file: main, folder: url)
    }

    private static func episodeFile(_ video: URL, showFolder: URL, folderSeason: Int?) -> EpisodeFile? {
        let name = video.deletingPathExtension().lastPathComponent
        let p = FilenameParser.parse(name)
        if let s = p.season, let e = p.episode {
            return EpisodeFile(url: video, season: s, episode: e)
        }

        // Season from a "Season 2" / "S02" / "Specials" folder between the show folder and the file.
        var season = folderSeason
        let rootPath = showFolder.standardizedFileURL.path
        var dir = video.deletingLastPathComponent().standardizedFileURL
        while dir.path.hasPrefix(rootPath), dir.path != rootPath, dir.path != "/" {
            let component = dir.lastPathComponent
            if let s = FilenameParser.parse(component).season { season = s; break }
            if component.lowercased().hasPrefix("special") { season = 0; break }
            dir = dir.deletingLastPathComponent()
        }

        if let e = p.episode {
            return EpisodeFile(url: video, season: season ?? 1, episode: e)
        }
        if let n = FilenameParser.leadingEpisodeNumber(name) {
            if season == nil && n >= 100 {
                return EpisodeFile(url: video, season: n / 100, episode: n % 100)
            }
            return EpisodeFile(url: video, season: season ?? 1, episode: n)
        }
        return nil
    }

    private static func makeMovie(title: String, year: Int?, added: Date, file: URL, folder: URL) -> LibraryItem {
        LibraryItem(id: "movie|\(FilenameParser.normalizedKey(title))|\(year ?? 0)", kind: .movie,
                    title: title, year: year, dateAdded: added, movieFile: file, episodes: [], folders: [folder])
    }

    private static func makeShow(title: String, year: Int?, added: Date, episodes: [EpisodeFile], folders: [URL]) -> LibraryItem {
        LibraryItem(id: "show|\(FilenameParser.normalizedKey(title))", kind: .show,
                    title: title, year: year, dateAdded: added, movieFile: nil,
                    episodes: episodes, folders: folders)
    }

    /// Several folders for the same show (e.g. one per season) become a single show.
    private static func merge(_ items: [LibraryItem]) -> [LibraryItem] {
        var byID: [String: LibraryItem] = [:]
        var order: [String] = []
        for item in items {
            guard var existing = byID[item.id] else {
                byID[item.id] = item
                order.append(item.id)
                continue
            }
            if item.kind == .show {
                let known = Set(existing.episodes.map { "\($0.season)x\($0.episode)" })
                existing.episodes += item.episodes.filter { !known.contains("\($0.season)x\($0.episode)") }
                existing.folders += item.folders
                existing.dateAdded = max(existing.dateAdded, item.dateAdded)
                existing.year = existing.year ?? item.year
                byID[item.id] = existing
            }
        }
        return order.compactMap { id in
            guard var item = byID[id] else { return nil }
            item.episodes.sort { ($0.season, $0.episode) < ($1.season, $1.episode) }
            return item
        }
    }

    // MARK: - File system helpers

    private static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .addedToDirectoryDateKey, .creationDateKey],
            options: [.skipsHiddenFiles])) ?? []
    }

    private static func videoFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            if isDirectory(url) {
                if ignoredFolderNames.contains(url.lastPathComponent.lowercased()) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if FilenameParser.isVideo(url), !FilenameParser.isSample(url), fileSize(url) > 0 {
                result.append(url)
            }
        }
        return result
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func dateAdded(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate ?? Date()
    }
}
