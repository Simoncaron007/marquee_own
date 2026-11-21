import SwiftUI

private let gridColumns = [
    GridItem(.adaptive(minimum: Theme.posterWidth, maximum: Theme.posterWidth + 24), spacing: 22, alignment: .top)
]

// MARK: - Movies / TV Shows

struct LibraryGridView: View {
    @Environment(Library.self) private var library
    let kind: MediaKind
    @State private var sort: SortKey = .title
    @State private var filter: WatchFilter = .all

    var body: some View {
        let all = library.list(of: kind)
        let filtered = all.filter { item in
            switch filter {
            case .all: return true
            case .watched: return library.isWatched(item)
            case .unwatched: return !library.isWatched(item)
            }
        }
        let list = library.sorted(filtered, by: sort)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(kind == .movie ? "Movies" : "TV Shows")
                        .font(.system(size: 30, weight: .bold))
                    Text("\(list.count)")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                    Picker("", selection: $filter) {
                        ForEach(WatchFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)

                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(SortKey.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if list.isEmpty {
                    Text(all.isEmpty ? "Nothing here yet." : "Nothing matches this filter.")
                        .foregroundStyle(Theme.tertiary)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 30) {
                        ForEach(list) { PosterCard(item: $0) }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.topBarHeight + 24)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Search

struct SearchResultsView: View {
    @Environment(Library.self) private var library
    let query: String

    var body: some View {
        let results = library.search(query)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Results for “\(query)”")
                    .font(.system(size: 26, weight: .bold))
                if results.isEmpty {
                    Text("Nothing in your library matches. Search looks at titles, original titles, cast and crew.")
                        .foregroundStyle(Theme.tertiary)
                } else {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 30) {
                        ForEach(results) { PosterCard(item: $0) }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.topBarHeight + 24)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(Library.self) private var library

    var body: some View {
        let entries = library.history
        let movieCount = library.movies.filter { library.isWatched($0) }.count
        let episodeCount = library.shows.reduce(0) { $0 + library.watchedEpisodeCount($1) }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("History").font(.system(size: 30, weight: .bold))
                    Text("\(movieCount) movies and \(episodeCount) episodes watched")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.tertiary)
                }

                if entries.isEmpty {
                    Text("Nothing played yet. Hit Play on anything and it shows up here.")
                        .foregroundStyle(Theme.tertiary)
                        .padding(.top, 20)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(entries) { HistoryRow(entry: $0) }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.topBarHeight + 24)
            .padding(.bottom, 48)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

struct HistoryRow: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    let entry: HistoryEntry
    @State private var hovering = false

    var body: some View {
        let meta = library.meta(entry.item)
        HStack(spacing: 14) {
            PosterArtwork(path: meta?.posterPath, title: library.displayTitle(entry.item))
                .frame(width: 40, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(library.displayTitle(entry.item))
                    .font(.system(size: 14, weight: .semibold))
                if let episode = entry.episode {
                    let name = library.episodeMeta(entry.item, episode)?.name
                    Text("S\(episode.season) · E\(episode.episode)" + (name.map { " — \($0)" } ?? ""))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                } else if let year = library.displayYear(entry.item) {
                    Text(String(year)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }

            Spacer()

            Text(entry.date, format: .relative(presentation: .named))
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)

            Image(systemName: entry.watched ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.watched ? Theme.accent : Theme.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(hovering ? Theme.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { router.open(entry.item) }
    }
}
