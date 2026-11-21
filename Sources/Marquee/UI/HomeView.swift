import SwiftUI

struct HomeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                if let hero = library.featured {
                    HeroView(item: hero)
                } else {
                    Color.clear.frame(height: Theme.topBarHeight + 20)
                }

                if library.items.isEmpty {
                    EmptyLibraryView()
                } else {
                    if !library.continueWatching.isEmpty {
                        PosterRow(title: "Continue Watching", items: library.continueWatching)
                    }
                    PosterRow(title: "Recently Added", items: library.recentlyAdded)
                    if !library.unwatchedMovies.isEmpty {
                        PosterRow(title: "Movies You Haven’t Seen", items: library.unwatchedMovies)
                    }
                    if !library.shows.isEmpty {
                        PosterRow(title: "TV Shows", items: library.sorted(library.shows, by: .title))
                    }
                    if !library.unidentified.isEmpty {
                        PosterRow(title: "Couldn’t Identify", items: library.unidentified,
                                  subtitle: "Right-click → Fix Match")
                    }
                }
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
    }
}

struct EmptyLibraryView: View {
    @Environment(Library.self) private var library

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack").font(.system(size: 40)).foregroundStyle(Theme.tertiary)
            Text(library.isScanning ? "Scanning your folder…" : "No movies or shows found yet")
                .font(.system(size: 17, weight: .semibold))
            Text(library.rootPath ?? "")
                .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}

// MARK: - Hero banner

struct HeroView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    let item: LibraryItem

    var body: some View {
        let meta = library.meta(item)
        ZStack(alignment: .bottomLeading) {
            TMDBImage(path: meta?.backdropPath, size: "w1280")
                .overlay {
                    LinearGradient(colors: [Theme.background, Theme.background.opacity(0)],
                                   startPoint: .bottom, endPoint: .center)
                }
                .overlay {
                    LinearGradient(colors: [Theme.background.opacity(0.9), Theme.background.opacity(0)],
                                   startPoint: .leading, endPoint: .init(x: 0.7, y: 0.5))
                }

            VStack(alignment: .leading, spacing: 12) {
                Text("RECENTLY ADDED")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.5)
                    .foregroundStyle(Theme.accent)
                Text(library.displayTitle(item))
                    .font(.system(size: 46, weight: .bold))
                    .lineLimit(2)
                Text(library.metaLine(item))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                if let overview = meta?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(3)
                        .lineSpacing(2)
                        .frame(maxWidth: 560, alignment: .leading)
                }
                HStack(spacing: 10) {
                    Button { library.play(item) } label: {
                        Label(playLabel, systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))

                    Button { router.open(item) } label: {
                        Label("More Info", systemImage: "info.circle")
                    }
                    .buttonStyle(PillButtonStyle())
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 20)
        }
        .frame(height: 500)
        .clipped()
    }

    private var playLabel: String {
        guard item.kind == .show, let next = library.nextEpisode(item) else { return "Play" }
        return "Play S\(next.season) E\(next.episode)"
    }
}

// MARK: - Rows

struct PosterRow: View {
    let title: String
    let items: [LibraryItem]
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).sectionTitle()
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, Theme.gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(items) { item in
                        PosterCard(item: item)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        }
    }
}
