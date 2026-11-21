import SwiftUI

struct DetailView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    let item: LibraryItem
    @State private var season = 1

    var body: some View {
        let meta = library.meta(item)
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header(meta)

                if let meta, !meta.cast.isEmpty {
                    CastRow(people: meta.cast)
                }

                if item.kind == .show {
                    episodes
                }

                if let meta, !meta.crew.isEmpty {
                    crew(meta.crew)
                }

                files
            }
            .padding(.bottom, 56)
        }
        .scrollIndicators(.hidden)
        .task(id: item.id) {
            season = library.nextEpisode(item)?.season ?? item.seasons.first ?? 1
        }
    }

    // MARK: Header

    private func header(_ meta: MediaMetadata?) -> some View {
        let title = library.displayTitle(item)
        let watched = library.isWatched(item)

        return HStack(alignment: .bottom, spacing: 34) {
            PosterArtwork(path: meta?.posterPath, title: title)
                .frame(width: 230, height: 345)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 42, weight: .bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let original = meta?.originalTitle, original != title {
                    Text(original)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                }

                Text(library.metaLine(item))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)

                if let tagline = meta?.tagline {
                    Text(tagline)
                        .font(.system(size: 15, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.accent.opacity(0.9))
                }

                if let overview = meta?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(3)
                        .frame(maxWidth: 680, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else if library.isUnidentified(item) {
                    Text("Marquee couldn’t find this on TMDB. Use Fix Match to pick the right title.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                } else if meta == nil {
                    Text("Fetching details…")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.tertiary)
                }

                if let summary = creditSummary(meta) {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }

                HStack(spacing: 10) {
                    Button { library.play(item) } label: {
                        Label(playLabel, systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: [])

                    Button {
                        library.setWatched(!watched, item: item)
                    } label: {
                        Label(watched ? "Watched" : "Mark as Watched",
                              systemImage: watched ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(PillButtonStyle())

                    Menu {
                        Button("Fix Match…") { router.fixing = item }
                        Button("Refresh Metadata") { library.refreshMetadata(item) }
                        Button("Show in Finder") { library.reveal(item) }
                        if let id = library.tmdbID(item),
                           let url = URL(string: "https://www.themoviedb.org/\(item.kind == .movie ? "movie" : "tv")/\(id)") {
                            Link("Open on TMDB", destination: url)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.13), in: Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 240)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            TMDBImage(path: meta?.backdropPath, size: "w1280")
                .frame(height: 560)
                .overlay {
                    LinearGradient(colors: [Theme.background, Theme.background.opacity(0.55), Theme.background.opacity(0.1)],
                                   startPoint: .bottom, endPoint: .top)
                }
                .overlay {
                    LinearGradient(colors: [Theme.background.opacity(0.85), Theme.background.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                }
        }
    }

    private var playLabel: String {
        guard item.kind == .show, let next = library.nextEpisode(item) else { return "Play" }
        return "Play S\(next.season) E\(next.episode)"
    }

    private func creditSummary(_ meta: MediaMetadata?) -> String? {
        guard let meta else { return nil }
        let role = item.kind == .movie ? "Director" : "Creator"
        let names = meta.crew.filter { $0.role == role }.map(\.name)
        guard !names.isEmpty else { return nil }
        let joined = ListFormatter.localizedString(byJoining: names)
        return item.kind == .movie ? "Directed by \(joined)" : "Created by \(joined)"
    }

    // MARK: Episodes

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Episodes").sectionTitle()
                Spacer()
                if item.seasons.count > 1 {
                    ForEach(item.seasons, id: \.self) { s in
                        Button(s == 0 ? "Specials" : "Season \(s)") { season = s }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(season == s ? Theme.accent : Color.white.opacity(0.08), in: Capsule())
                            .foregroundStyle(season == s ? Color.black : Color.white)
                    }
                }
            }

            let next = library.nextEpisode(item)
            LazyVStack(spacing: 4) {
                ForEach(item.episodes.filter { $0.season == season }) { episode in
                    EpisodeRow(item: item, episode: episode, isNext: episode == next)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: Crew & files

    private func crew(_ people: [Person]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Crew").sectionTitle()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16, alignment: .leading)],
                      alignment: .leading, spacing: 14) {
                ForEach(people, id: \.uid) { person in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).font(.system(size: 13, weight: .medium))
                        Text(person.role).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { router.searchPerson(person.name) }
                    .help("Find more with \(person.name) in your library")
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ON DISK")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(Theme.tertiary)
            ForEach((item.movieFile.map { [$0] } ?? item.folders), id: \.self) { url in
                Text(url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

// MARK: - Cast

struct CastRow: View {
    @Environment(Router.self) private var router
    let people: [Person]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cast").sectionTitle()
                .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(people, id: \.uid) { person in
                        VStack(spacing: 7) {
                            TMDBImage(path: person.profilePath, size: "w185", placeholderSymbol: "person.fill")
                                .frame(width: 96, height: 96)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Theme.hairline))
                            Text(person.name)
                                .font(.system(size: 12, weight: .medium))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text(person.role)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.tertiary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(width: 108)
                        .contentShape(Rectangle())
                        .onTapGesture { router.searchPerson(person.name) }
                        .help("Find more with \(person.name) in your library")
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Episode row

struct EpisodeRow: View {
    @Environment(Library.self) private var library
    let item: LibraryItem
    let episode: EpisodeFile
    let isNext: Bool
    @State private var hovering = false

    var body: some View {
        let meta = library.episodeMeta(item, episode)
        let watched = library.isWatched(item, episode)

        HStack(alignment: .top, spacing: 18) {
            ZStack {
                TMDBImage(path: meta?.stillPath, size: "w300", placeholderSymbol: "tv")
                    .opacity(watched && !hovering ? 0.55 : 1)
                if hovering {
                    Color.black.opacity(0.3)
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 192, height: 108)
            .overlay(alignment: .bottom) {
                if isNext { Rectangle().fill(Theme.accent).frame(height: 3) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(episode.episode). \(meta?.name ?? "Episode \(episode.episode)")")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if isNext {
                        Text("UP NEXT")
                            .font(.system(size: 9, weight: .heavy))
                            .kerning(1)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                    Spacer()
                    Text(detailLine(meta))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
                if let overview = meta?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(3)
                        .lineSpacing(2)
                } else {
                    Text(episode.url.lastPathComponent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Button {
                library.setWatched(!watched, item: item, episode: episode)
            } label: {
                Image(systemName: watched ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(watched ? Theme.accent : Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help(watched ? "Mark as unwatched" : "Mark as watched")
        }
        .padding(10)
        .background(hovering ? Theme.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture { library.play(item, episode: episode) }
        .contextMenu {
            Button("Play") { library.play(item, episode: episode) }
            Button(watched ? "Mark as Unwatched" : "Mark as Watched") {
                library.setWatched(!watched, item: item, episode: episode)
            }
            Button("Mark This and Earlier as Watched") { library.markPreviousWatched(item, upTo: episode) }
            Divider()
            Button("Show in Finder") { Player.reveal([episode.url]) }
        }
    }

    private func detailLine(_ meta: EpisodeMeta?) -> String {
        var parts: [String] = []
        if let runtime = meta?.runtime, runtime > 0 { parts.append(formatRuntime(runtime)) }
        if let air = meta?.airDate, let date = try? Date(air + "T00:00:00Z", strategy: .iso8601) {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: "  ·  ")
    }
}
