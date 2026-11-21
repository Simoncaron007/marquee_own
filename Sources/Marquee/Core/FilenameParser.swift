import Foundation

/// What we can learn from a single file or folder name such as
/// "Koyaanisqatsi (1982) [BluRay] [1080p] [YTS.AM]" or "Broadchurch.S01E03.1080p.BluRay.x265-RARBG".
struct ParsedName: Equatable {
    var title: String
    var year: Int?
    var season: Int?
    var episode: Int?
}

enum FilenameParser {
    static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "avi", "mov", "wmv", "mpg", "mpeg", "ts", "m2ts",
        "webm", "flv", "ogm", "divx", "vob"
    ]

    static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    static func isSample(_ url: URL) -> Bool {
        firstMatch(samplePattern, in: url.deletingPathExtension().lastPathComponent) != nil
    }

    // MARK: - Patterns

    private static func rx(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let samplePattern = rx(#"(^|[^a-z])sample([^a-z]|$)"#)
    private static let seasonEpisode = rx(#"\bS(\d{1,2})[ ._-]?E(\d{1,3})(?!\d)"#)
    private static let crossEpisode = rx(#"\b(\d{1,2})x(\d{2,3})\b"#)
    private static let seasonCompact = rx(#"\bS(\d{1,2})\b"#)
    private static let seasonWord = rx(#"\b(?:season|saison|series|staffel|seizoen|temporada|stagione)[ ._-]?(\d{1,2})\b"#)
    private static let episodeWord = rx(#"\b(?:episode|episodio|épisode|aflevering|folge|ep)[ ._-]?(\d{1,3})\b|\bE(\d{1,3})\b"#)
    private static let leadingNumber = rx(#"^(\d{1,3})(?=[ ._-]|$)"#)
    private static let yearPattern = rx(#"[(\[]?\b((?:19|20)\d{2})\b[)\]]?"#)
    private static let junk = rx(#"\b(?:2160p|1080p|1080i|720p|576p|480p|4k|uhd|hdr|hdr10|bluray|blu-ray|bdrip|brrip|bdremux|remux|web-?dl|web-?rip|hdtv|hdrip|dvdrip|dvdscr|xvid|x264|x265|h\.?264|h\.?265|hevc|aac|ac3|eac3|dts|10bit|8bit|remastered|repack|proper|unrated|imax|criterion|complete|integrale|amzn|yts|rarbg|vostfr|truefrench|subbed|dubbed)\b"#)
    private static let leadingTag = rx(#"^\s*(?:\[[^\]]*\]|www\.\S+)\s*[-–]?\s*"#)

    // MARK: - Parsing

    static func parse(_ raw: String) -> ParsedName {
        var name = raw.replacingOccurrences(of: "_", with: " ")
        let dots = name.filter { $0 == "." }.count
        let spaces = name.filter { $0 == " " }.count
        if dots >= 2 && dots > spaces {
            name = name.replacingOccurrences(of: ".", with: " ")
        }
        name = leadingTag.stringByReplacingMatches(
            in: name, range: NSRange(location: 0, length: (name as NSString).length), withTemplate: "")

        let ns = name as NSString
        var cut = ns.length
        var season: Int?
        var episode: Int?
        var year: Int?

        if let m = firstMatch(seasonEpisode, in: name) ?? firstMatch(crossEpisode, in: name) {
            season = int(m, 1, ns)
            episode = int(m, 2, ns)
            cut = min(cut, m.range.location)
        } else {
            let candidates = [firstMatch(seasonWord, in: name), firstMatch(seasonCompact, in: name)].compactMap { $0 }
            if let m = candidates.min(by: { $0.range.location < $1.range.location }) {
                season = int(m, 1, ns)
                cut = min(cut, m.range.location)
            }
        }

        if episode == nil, let m = firstMatch(episodeWord, in: name) {
            episode = int(m, 1, ns) ?? int(m, 2, ns)
        }

        // Years: a number at the very start belongs to the title ("1917", "2001 A Space Odyssey").
        let maxYear = Calendar.current.component(.year, from: Date()) + 1
        let years = yearPattern.matches(in: name, range: NSRange(location: 0, length: ns.length)).filter { m in
            guard let y = int(m, 1, ns), y >= 1900, y <= maxYear else { return false }
            return m.range.location > 0
        }
        let bracketed = years.first { m in
            let s = ns.substring(with: m.range)
            return s.hasPrefix("(") || s.hasPrefix("[")
        }
        if let m = bracketed ?? years.last {
            year = int(m, 1, ns)
            cut = min(cut, m.range.location)
        }

        if let m = firstMatch(junk, in: name), m.range.location > 0 {
            cut = min(cut, m.range.location)
        }

        let bracket = ns.rangeOfCharacter(from: CharacterSet(charactersIn: "[{("))
        if bracket.location != NSNotFound, bracket.location > 0 {
            cut = min(cut, bracket.location)
        }

        return ParsedName(title: cleanTitle(ns.substring(to: cut)), year: year, season: season, episode: episode)
    }

    /// "01 - Into the Unknown" → 1, "105 Pilot" → 105 (caller may split into S1E05).
    static func leadingEpisodeNumber(_ raw: String) -> Int? {
        let ns = raw as NSString
        guard let m = leadingNumber.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return int(m, 1, ns)
    }

    /// Key used to merge things that are the same title ("Ugly Betty" season folders, accents, punctuation).
    static func normalizedKey(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "&", with: "and")
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    // MARK: - Helpers

    private static func cleanTitle(_ s: String) -> String {
        let trimSet = CharacterSet(charactersIn: " -–_.,:;+([{").union(.whitespacesAndNewlines)
        let collapsed = s.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: trimSet)
    }

    private static func firstMatch(_ regex: NSRegularExpression, in s: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    private static func int(_ m: NSTextCheckingResult, _ group: Int, _ ns: NSString) -> Int? {
        guard group < m.numberOfRanges else { return nil }
        let r = m.range(at: group)
        guard r.location != NSNotFound else { return nil }
        return Int(ns.substring(with: r))
    }
}
