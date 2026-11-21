import Foundation

enum TMDBError: LocalizedError {
    case unauthorized
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "TMDB rejected the API key. Check it in Settings."
        case .http(let code): return "TMDB returned an error (\(code))."
        }
    }
}

// MARK: - Wire types

struct TMDBSearchResult: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let overview: String?

    var displayTitle: String { title ?? name ?? "Untitled" }
    var year: Int? { Int((releaseDate ?? firstAirDate ?? "").prefix(4)) }
}

private struct TMDBPage<T: Decodable>: Decodable { let results: [T] }
private struct TMDBGenre: Decodable { let name: String }
private struct TMDBNetwork: Decodable { let name: String }
private struct TMDBCreator: Decodable { let id: Int; let name: String; let profilePath: String? }
private struct TMDBCast: Decodable { let id: Int; let name: String; let character: String?; let profilePath: String?; let order: Int? }
private struct TMDBCrew: Decodable { let id: Int; let name: String; let job: String?; let profilePath: String? }
private struct TMDBCredits: Decodable { let cast: [TMDBCast]?; let crew: [TMDBCrew]? }

private struct TMDBMovie: Decodable {
    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let tagline: String?
    let releaseDate: String?
    let runtime: Int?
    let genres: [TMDBGenre]?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let credits: TMDBCredits?
}

private struct TMDBShow: Decodable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let tagline: String?
    let firstAirDate: String?
    let lastAirDate: String?
    let episodeRunTime: [Int]?
    let genres: [TMDBGenre]?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let numberOfSeasons: Int?
    let status: String?
    let createdBy: [TMDBCreator]?
    let networks: [TMDBNetwork]?
    let credits: TMDBCredits?
}

private struct TMDBSeason: Decodable { let episodes: [TMDBEpisode] }
private struct TMDBEpisode: Decodable {
    let episodeNumber: Int
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let stillPath: String?
    let airDate: String?
    let runtime: Int?
}

// MARK: - Client

/// Talks to themoviedb.org. Accepts either a v3 "API Key" or a v4 "API Read Access Token".
struct TMDBClient {
    let credential: String
    let language: String

    private static let crewJobs = [
        "Director", "Screenplay", "Writer", "Novel", "Story", "Director of Photography",
        "Original Music Composer", "Editor", "Producer", "Executive Producer"
    ]

    func search(_ query: String, year: Int?, kind: MediaKind) async throws -> [TMDBSearchResult] {
        var params = ["query": query, "include_adult": "false", "language": language]
        if let year { params[kind == .movie ? "year" : "first_air_date_year"] = String(year) }
        let page: TMDBPage<TMDBSearchResult> = try await get(kind == .movie ? "/search/movie" : "/search/tv", params)
        return page.results
    }

    /// Picks the most plausible result: exact title and matching year win.
    func bestMatch(title: String, year: Int?, kind: MediaKind) async throws -> Int? {
        var results = try await search(title, year: year, kind: kind)
        if results.isEmpty, year != nil {
            results = try await search(title, year: nil, kind: kind)
        }
        let wanted = FilenameParser.normalizedKey(title)
        let scored = results.prefix(10).enumerated().map { index, r -> (Int, Int) in
            var score = 0
            let names = [r.title, r.name, r.originalTitle, r.originalName].compactMap { $0 }.map(FilenameParser.normalizedKey)
            if names.contains(wanted) { score += 4 }
            if let year, let ry = r.year, abs(ry - year) <= 1 { score += 3 }
            score -= index  // TMDB's own relevance order as tie-breaker
            return (score, r.id)
        }
        return scored.max { $0.0 < $1.0 }?.1
    }

    func movie(_ id: Int) async throws -> MediaMetadata {
        let m: TMDBMovie = try await get("/movie/\(id)", ["language": language, "append_to_response": "credits"])
        var overview = m.overview ?? ""
        if overview.isEmpty, !language.hasPrefix("en") {
            let en: TMDBMovie? = try? await get("/movie/\(id)", ["language": "en-US"])
            overview = en?.overview ?? ""
        }
        return MediaMetadata(
            tmdbID: m.id, kind: .movie, title: m.title,
            originalTitle: m.originalTitle, overview: overview,
            tagline: m.tagline.flatMap { $0.isEmpty ? nil : $0 },
            year: Self.year(m.releaseDate), endYear: nil, runtime: m.runtime,
            genres: (m.genres ?? []).map(\.name),
            posterPath: m.posterPath, backdropPath: m.backdropPath, rating: m.voteAverage,
            cast: Self.cast(m.credits), crew: Self.crew(m.credits, creators: []),
            network: nil, status: nil, seasonCount: nil)
    }

    func show(_ id: Int) async throws -> MediaMetadata {
        let s: TMDBShow = try await get("/tv/\(id)", ["language": language, "append_to_response": "credits"])
        var overview = s.overview ?? ""
        if overview.isEmpty, !language.hasPrefix("en") {
            let en: TMDBShow? = try? await get("/tv/\(id)", ["language": "en-US"])
            overview = en?.overview ?? ""
        }
        let creators = (s.createdBy ?? []).map { Person(id: $0.id, name: $0.name, role: "Creator", profilePath: $0.profilePath) }
        let ended = s.status == "Ended" || s.status == "Canceled"
        return MediaMetadata(
            tmdbID: s.id, kind: .show, title: s.name,
            originalTitle: s.originalName, overview: overview,
            tagline: s.tagline.flatMap { $0.isEmpty ? nil : $0 },
            year: Self.year(s.firstAirDate), endYear: ended ? Self.year(s.lastAirDate) : nil,
            runtime: s.episodeRunTime?.first,
            genres: (s.genres ?? []).map(\.name),
            posterPath: s.posterPath, backdropPath: s.backdropPath, rating: s.voteAverage,
            cast: Self.cast(s.credits), crew: Self.crew(s.credits, creators: creators),
            network: s.networks?.first?.name, status: s.status, seasonCount: s.numberOfSeasons)
    }

    func season(showID: Int, season: Int) async throws -> [EpisodeMeta] {
        let s: TMDBSeason = try await get("/tv/\(showID)/season/\(season)", ["language": language])
        return s.episodes.map {
            EpisodeMeta(season: $0.seasonNumber, episode: $0.episodeNumber, name: $0.name,
                        overview: $0.overview, stillPath: $0.stillPath, airDate: $0.airDate, runtime: $0.runtime)
        }
    }

    // MARK: Helpers

    private static func year(_ date: String?) -> Int? {
        guard let date, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

    private static func cast(_ credits: TMDBCredits?) -> [Person] {
        (credits?.cast ?? [])
            .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
            .prefix(20)
            .map { Person(id: $0.id, name: $0.name, role: $0.character ?? "", profilePath: $0.profilePath) }
    }

    private static func crew(_ credits: TMDBCredits?, creators: [Person]) -> [Person] {
        var seen = Set(creators.map(\.uid))
        var result = creators
        let relevant = (credits?.crew ?? [])
            .filter { crewJobs.contains($0.job ?? "") }
            .sorted { (crewJobs.firstIndex(of: $0.job ?? "") ?? 99) < (crewJobs.firstIndex(of: $1.job ?? "") ?? 99) }
        for c in relevant {
            let person = Person(id: c.id, name: c.name, role: c.job ?? "", profilePath: c.profilePath)
            if seen.insert(person.uid).inserted { result.append(person) }
        }
        return Array(result.prefix(12))
    }

    private func get<T: Decodable>(_ path: String, _ params: [String: String], attempt: Int = 0) async throws -> T {
        let isBearer = credential.count > 40
        var components = URLComponents(string: "https://api.themoviedb.org/3" + path)!
        var items = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        if !isBearer { items.append(URLQueryItem(name: "api_key", value: credential)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if isBearer { request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw TMDBError.unauthorized }
        if status == 429, attempt < 3 {
            try await Task.sleep(for: .seconds(2))
            return try await get(path, params, attempt: attempt + 1)
        }
        guard (200..<300).contains(status) else { throw TMDBError.http(status) }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
