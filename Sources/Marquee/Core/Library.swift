import AppKit
import Observation

/// The app's single source of truth: what's on disk, what TMDB says about it, and what you've watched.
@MainActor
@Observable
final class Library {
    static let languages: [MetadataLanguage] = [
        .init(code: "en-US", name: "English"),
        .init(code: "fr-FR", name: "Français"),
        .init(code: "nl-NL", name: "Nederlands"),
        .init(code: "de-DE", name: "Deutsch"),
        .init(code: "es-ES", name: "Español"),
        .init(code: "it-IT", name: "Italiano"),
        .init(code: "ja-JP", name: "日本語")
    ]

    private(set) var items: [LibraryItem] = []
    private(set) var state = PersistedState()
    private(set) var isScanning = false
    private(set) var matchProgress: (done: Int, total: Int)?
    var errorMessage: String?

    var rootPath: String? {
        didSet { UserDefaults.standard.set(rootPath, forKey: "rootPath") }
    }
    var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "tmdbKey")
            errorMessage = nil
            scheduleMatching()
        }
    }
    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    var markWatchedOnPlay: Bool {
        didSet { UserDefaults.standard.set(markWatchedOnPlay, forKey: "markWatchedOnPlay") }
    }

    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    @ObservationIgnored private var matchTask: Task<Void, Never>?
    @ObservationIgnored private var matchDelayTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isMatching = false
    @ObservationIgnored private var rematchRequested = false
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        rootPath = defaults.string(forKey: "rootPath")
        apiKey = defaults.string(forKey: "tmdbKey") ?? ""
        language = defaults.string(forKey: "language") ?? "en-US"
        markWatchedOnPlay = defaults.object(forKey: "markWatchedOnPlay") as? Bool ?? true

        if let data = try? Data(contentsOf: AppPaths.stateFile),
           let saved = try? JSONDecoder().decode(PersistedState.self, from: data) {
            state = saved
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow(synchronously: true) }
        }
    }

    var isConfigured: Bool { rootPath != nil && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Folder & scanning

    func start() {
        guard let rootPath else { return }
        let watcher = FolderWatcher { [weak self] in
            Task { @MainActor in self?.scheduleRescan() }
        }
        watcher.start(path: rootPath)
        self.watcher = watcher
        rescan()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder that holds your movies and TV shows"
        if let rootPath { panel.directoryURL = URL(fileURLWithPath: rootPath) }
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
            start()
        }
    }

    func rescan() {
        guard let rootPath else { return }
        isScanning = true
        let root = URL(fileURLWithPath: rootPath)
        Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                LibraryScanner.scan(root: root)
            }.value
            if scanned != self.items { self.items = scanned }
            self.isScanning = false
            self.matchMissing()
        }
    }

    /// Throttled: while a torrent is downloading the folder changes constantly,
    /// so rescan at most every few seconds rather than waiting for silence.
    private func scheduleRescan() {
        guard rescanTask == nil else { return }
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.rescanTask = nil
            self?.rescan()
        }
    }

    // MARK: - Matching with TMDB

    private var client: TMDBClient {
        TMDBClient(credential: apiKey.trimmingCharacters(in: .whitespacesAndNewlines), language: language)
    }

    private func scheduleMatching() {
        matchDelayTask?.cancel()
        matchDelayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.matchMissing()
        }
    }

    /// Identifies new items. With `refresh`, re-downloads all metadata (e.g. after changing language).
    func matchMissing(refresh: Bool = false) {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if refresh {
            state.unmatchable.removeAll()
            matchTask?.cancel()
            isMatching = false
        }
        // Already running: just ask for one more pass when it finishes.
        if isMatching {
            rematchRequested = true
            return
        }
        isMatching = true
        matchTask = Task {
            var refreshPass = refresh
            repeat {
                rematchRequested = false
                await runMatching(refresh: refreshPass)
                refreshPass = false
            } while rematchRequested && !Task.isCancelled
            if !Task.isCancelled { isMatching = false }
        }
    }

    private func runMatching(refresh: Bool) async {
        let pending = refresh ? items : items.filter(needsWork)
        guard !pending.isEmpty else { return }
        let client = self.client
        matchProgress = (0, pending.count)
        for (index, item) in pending.enumerated() {
            if Task.isCancelled { return }
            do {
                try await process(item, client: client, refresh: refresh)
            } catch TMDBError.unauthorized {
                errorMessage = TMDBError.unauthorized.errorDescription
                break
            } catch {
                // Network hiccup: skip, it'll be retried on the next scan.
            }
            matchProgress = (index + 1, pending.count)
            scheduleSave()
        }
        if !Task.isCancelled { matchProgress = nil }
    }

    private func needsWork(_ item: LibraryItem) -> Bool {
        if state.unmatchable.contains(item.id) { return false }
        guard let id = state.matches[item.id] else { return true }
        switch item.kind {
        case .movie:
            return state.movieMeta[id] == nil
        case .show:
            return state.showMeta[id] == nil || item.seasons.contains { state.seasonMeta[seasonKey(id, $0)] == nil }
        }
    }

    private func process(_ item: LibraryItem, client: TMDBClient, refresh: Bool) async throws {
        var tmdbID = state.matches[item.id]
        if tmdbID == nil {
            tmdbID = try await client.bestMatch(title: item.title, year: item.year, kind: item.kind)
            guard let found = tmdbID else {
                state.unmatchable.insert(item.id)
                return
            }
            assignMatch(found, to: item)
        }
        guard let tmdbID else { return }
        try await fetchDetails(tmdbID, for: item, client: client, refresh: refresh)
    }

    private func fetchDetails(_ id: Int, for item: LibraryItem, client: TMDBClient, refresh: Bool) async throws {
        switch item.kind {
        case .movie:
            if refresh || state.movieMeta[id] == nil {
                state.movieMeta[id] = try await client.movie(id)
            }
        case .show:
            if refresh || state.showMeta[id] == nil {
                state.showMeta[id] = try await client.show(id)
            }
            for season in item.seasons where refresh || state.seasonMeta[seasonKey(id, season)] == nil {
                do {
                    state.seasonMeta[seasonKey(id, season)] = try await client.season(showID: id, season: season)
                } catch TMDBError.http(404) {
                    state.seasonMeta[seasonKey(id, season)] = []   // season unknown to TMDB
                }
            }
        }
    }

    private func assignMatch(_ id: Int, to item: LibraryItem) {
        // Keep watch history when an item goes from unidentified → identified, or gets re-matched.
        let oldMovieKey = watchKey(item)
        let oldEpisodeKeys = item.episodes.map { watchKey(item, $0) }
        state.matches[item.id] = id
        state.unmatchable.remove(item.id)
        if item.kind == .movie { migrateWatch(from: oldMovieKey, to: watchKey(item)) }
        for (episode, oldKey) in zip(item.episodes, oldEpisodeKeys) {
            migrateWatch(from: oldKey, to: watchKey(item, episode))
        }
    }

    private func migrateWatch(from old: String, to new: String) {
        guard old != new, let record = state.watch.removeValue(forKey: old) else { return }
        if state.watch[new] == nil { state.watch[new] = record }
    }

    // MARK: Fix match

    func searchTMDB(_ query: String, year: Int?, kind: MediaKind) async throws -> [TMDBSearchResult] {
        try await client.search(query, year: year, kind: kind)
    }

    func applyMatch(_ result: TMDBSearchResult, to item: LibraryItem) {
        assignMatch(result.id, to: item)
        state.lockedMatches.insert(item.id)
        scheduleSave()
        let client = self.client
        Task {
            do { try await fetchDetails(result.id, for: item, client: client, refresh: false) }
            catch { errorMessage = error.localizedDescription }
            scheduleSave()
        }
    }

    func refreshMetadata(_ item: LibraryItem) {
        guard let id = state.matches[item.id] else { matchMissing(); return }
        let client = self.client
        Task {
            try? await fetchDetails(id, for: item, client: client, refresh: true)
            scheduleSave()
        }
    }

    // MARK: - Lookups

    func item(id: String) -> LibraryItem? { items.first { $0.id == id } }

    func tmdbID(_ item: LibraryItem) -> Int? { state.matches[item.id] }

    func meta(_ item: LibraryItem) -> MediaMetadata? {
        guard let id = state.matches[item.id] else { return nil }
        return item.kind == .movie ? state.movieMeta[id] : state.showMeta[id]
    }

    func displayTitle(_ item: LibraryItem) -> String { meta(item)?.title ?? item.title }
    func displayYear(_ item: LibraryItem) -> Int? { meta(item)?.year ?? item.year }
    func isUnidentified(_ item: LibraryItem) -> Bool { state.unmatchable.contains(item.id) }

    func episodeMeta(_ item: LibraryItem, _ episode: EpisodeFile) -> EpisodeMeta? {
        guard let id = state.matches[item.id] else { return nil }
        return state.seasonMeta[seasonKey(id, episode.season)]?.first { $0.episode == episode.episode }
    }

    private func seasonKey(_ id: Int, _ season: Int) -> String { "\(id):\(season)" }

    /// "1982 · 1h 27m · Documentary, Music · ★ 7.9"
    func metaLine(_ item: LibraryItem) -> String {
        var parts: [String] = []
        let info = meta(item)
        if let year = displayYear(item) {
            if item.kind == .show, let info, info.status != nil {
                parts.append(info.endYear.map { $0 == year ? "\(year)" : "\(year)–\($0)" } ?? "\(year)–")
            } else {
                parts.append(String(year))
            }
        }
        if item.kind == .show {
            let count = item.seasons.count
            parts.append(count == 1 ? "1 season" : "\(count) seasons")
        } else if let runtime = info?.runtime, runtime > 0 {
            parts.append(formatRuntime(runtime))
        }
        if let genres = info?.genres, !genres.isEmpty { parts.append(genres.prefix(3).joined(separator: ", ")) }
        if let network = info?.network { parts.append(network) }
        if let rating = info?.rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - Watch tracking

    private func watchKey(_ item: LibraryItem) -> String {
        if let id = state.matches[item.id] { return "m\(id)" }
        return "m:\(item.id)"
    }

    private func watchKey(_ item: LibraryItem, _ episode: EpisodeFile) -> String {
        if let id = state.matches[item.id] { return "t\(id):\(episode.season):\(episode.episode)" }
        return "t:\(item.id):\(episode.season):\(episode.episode)"
    }

    func isWatched(_ item: LibraryItem) -> Bool {
        switch item.kind {
        case .movie: return state.watch[watchKey(item)]?.watched == true
        case .show: return !item.episodes.isEmpty && item.episodes.allSatisfy { isWatched(item, $0) }
        }
    }

    func isWatched(_ item: LibraryItem, _ episode: EpisodeFile) -> Bool {
        state.watch[watchKey(item, episode)]?.watched == true
    }

    func watchedEpisodeCount(_ item: LibraryItem) -> Int {
        item.episodes.filter { isWatched(item, $0) }.count
    }

    func lastPlayed(_ item: LibraryItem) -> Date? {
        switch item.kind {
        case .movie: return state.watch[watchKey(item)]?.lastPlayed
        case .show: return item.episodes.compactMap { state.watch[watchKey(item, $0)]?.lastPlayed }.max()
        }
    }

    func setWatched(_ watched: Bool, item: LibraryItem) {
        switch item.kind {
        case .movie: updateWatch(watchKey(item)) { Self.mark(&$0, watched) }
        case .show: item.episodes.forEach { setWatched(watched, item: item, episode: $0) }
        }
    }

    func setWatched(_ watched: Bool, item: LibraryItem, episode: EpisodeFile) {
        updateWatch(watchKey(item, episode)) { Self.mark(&$0, watched) }
    }

    func markPreviousWatched(_ item: LibraryItem, upTo episode: EpisodeFile) {
        for e in item.episodes where (e.season, e.episode) <= (episode.season, episode.episode) {
            setWatched(true, item: item, episode: e)
        }
    }

    private static func mark(_ record: inout WatchRecord, _ watched: Bool) {
        record.watched = watched
        record.watchedDate = watched ? (record.watchedDate ?? Date()) : nil
    }

    private func updateWatch(_ key: String, _ change: (inout WatchRecord) -> Void) {
        var record = state.watch[key] ?? WatchRecord()
        change(&record)
        state.watch[key] = record
        scheduleSave()
    }

    /// The episode Play should start: the first unwatched one after the last one you watched.
    func nextEpisode(_ item: LibraryItem) -> EpisodeFile? {
        let episodes = item.episodes
        if let last = episodes.lastIndex(where: { isWatched(item, $0) }),
           let next = episodes[(last + 1)...].first(where: { !isWatched(item, $0) }) {
            return next
        }
        return episodes.first { !isWatched(item, $0) }
    }

    // MARK: - Playback

    func play(_ item: LibraryItem) {
        switch item.kind {
        case .movie:
            guard let file = item.movieFile else { return }
            launch(file) { updateWatch(watchKey(item), $0) }
        case .show:
            guard let episode = nextEpisode(item) ?? item.episodes.first else { return }
            play(item, episode: episode)
        }
    }

    func play(_ item: LibraryItem, episode: EpisodeFile) {
        launch(episode.url) { updateWatch(watchKey(item, episode), $0) }
    }

    private func launch(_ file: URL, record: ((inout WatchRecord) -> Void) -> Void) {
        guard FileManager.default.fileExists(atPath: file.path) else {
            errorMessage = "\(file.lastPathComponent) has moved. Rescanning…"
            rescan()
            return
        }
        Player.open(file)
        let markWatched = markWatchedOnPlay
        record { r in
            r.lastPlayed = Date()
            r.playCount += 1
            if markWatched { Self.mark(&r, true) }
        }
    }

    func reveal(_ item: LibraryItem) {
        if let file = item.movieFile { Player.reveal([file]) } else { Player.reveal(item.folders) }
    }

    // MARK: - Collections for the UI

    var movies: [LibraryItem] { items.filter { $0.kind == .movie } }
    var shows: [LibraryItem] { items.filter { $0.kind == .show } }

    func list(of kind: MediaKind) -> [LibraryItem] { kind == .movie ? movies : shows }

    var recentlyAdded: [LibraryItem] {
        Array(items.sorted { $0.dateAdded > $1.dateAdded }.prefix(20))
    }

    var continueWatching: [LibraryItem] {
        items.filter { item in
            switch item.kind {
            case .show: return watchedEpisodeCount(item) > 0 && !isWatched(item)
            case .movie: return lastPlayed(item) != nil && !isWatched(item)
            }
        }
        .sorted { (lastPlayed($0) ?? .distantPast) > (lastPlayed($1) ?? .distantPast) }
    }

    var unwatchedMovies: [LibraryItem] {
        sorted(movies.filter { !isWatched($0) }, by: .title)
    }

    var unidentified: [LibraryItem] { items.filter(isUnidentified) }

    /// Most recently added item that has a backdrop, for the big banner on Home.
    var featured: LibraryItem? {
        items.filter { meta($0)?.backdropPath != nil }.max { $0.dateAdded < $1.dateAdded }
    }

    var history: [HistoryEntry] {
        var entries: [HistoryEntry] = []
        for item in items {
            switch item.kind {
            case .movie:
                if let r = state.watch[watchKey(item)], let date = r.lastPlayed ?? r.watchedDate {
                    entries.append(HistoryEntry(id: item.id, item: item, episode: nil, date: date, watched: r.watched))
                }
            case .show:
                for e in item.episodes {
                    if let r = state.watch[watchKey(item, e)], let date = r.lastPlayed ?? r.watchedDate {
                        entries.append(HistoryEntry(id: e.id, item: item, episode: e, date: date, watched: r.watched))
                    }
                }
            }
        }
        return Array(entries.sorted { $0.date > $1.date }.prefix(200))
    }

    func sorted(_ list: [LibraryItem], by key: SortKey) -> [LibraryItem] {
        switch key {
        case .title:
            return list.sorted { sortTitle($0).localizedStandardCompare(sortTitle($1)) == .orderedAscending }
        case .added:
            return list.sorted { $0.dateAdded > $1.dateAdded }
        case .year:
            return list.sorted { (displayYear($0) ?? 0) > (displayYear($1) ?? 0) }
        case .rating:
            return list.sorted { (meta($0)?.rating ?? 0) > (meta($1)?.rating ?? 0) }
        }
    }

    private func sortTitle(_ item: LibraryItem) -> String {
        let title = displayTitle(item)
        for prefix in ["The ", "A ", "An ", "Le ", "La ", "Les ", "L'"] where title.hasPrefix(prefix) {
            return String(title.dropFirst(prefix.count))
        }
        return title
    }

    /// Matches titles, original titles, and cast & crew names.
    func search(_ query: String) -> [LibraryItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let hits = items.filter { item in
            if item.title.localizedStandardContains(q) || displayTitle(item).localizedStandardContains(q) { return true }
            guard let info = meta(item) else { return false }
            if info.originalTitle?.localizedStandardContains(q) == true { return true }
            return (info.cast + info.crew).contains { $0.name.localizedStandardContains(q) }
        }
        return sorted(hits, by: .title)
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow(synchronously: Bool = false) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = AppPaths.stateFile
        if synchronously {
            try? data.write(to: url, options: .atomic)
        } else {
            DispatchQueue.global(qos: .utility).async { try? data.write(to: url, options: .atomic) }
        }
    }
}
