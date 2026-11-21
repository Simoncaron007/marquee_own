import SwiftUI

struct PosterCard: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    let item: LibraryItem
    var width: CGFloat = Theme.posterWidth
    @State private var hovering = false

    var body: some View {
        let meta = library.meta(item)
        let title = library.displayTitle(item)

        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                PosterArtwork(path: meta?.posterPath, title: title)
                if hovering {
                    Color.black.opacity(0.35)
                    Button { library.play(item) } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 46))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help(item.kind == .show ? "Play next episode" : "Play")
                }
            }
            .frame(width: width, height: width * 1.5)
            .overlay(alignment: .topTrailing) { badge.padding(7) }
            .overlay(alignment: .bottom) { progressBar }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(hovering ? Theme.accent : Theme.hairline, lineWidth: hovering ? 2 : 1)
            }
            .shadow(color: .black.opacity(hovering ? 0.5 : 0.25), radius: hovering ? 14 : 6, y: 4)
            .scaleEffect(hovering ? 1.03 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .onTapGesture { router.open(item) }
        .contextMenu { ItemMenu(item: item) }
    }

    private var subtitle: String {
        if library.isUnidentified(item) { return "Not identified" }
        let year = library.displayYear(item).map(String.init) ?? ""
        guard item.kind == .show else { return year }
        let count = item.episodes.count
        let eps = count == 1 ? "1 episode" : "\(count) episodes"
        return year.isEmpty ? eps : "\(year) · \(eps)"
    }

    @ViewBuilder private var badge: some View {
        if library.isWatched(item) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, Theme.accent)
                .shadow(radius: 3)
        } else if item.kind == .show {
            let unwatched = item.episodes.count - library.watchedEpisodeCount(item)
            Text("\(unwatched)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.accent, in: Capsule())
                .help("\(unwatched) unwatched episodes")
        }
    }

    @ViewBuilder private var progressBar: some View {
        if item.kind == .show, !library.isWatched(item) {
            let watched = library.watchedEpisodeCount(item)
            if watched > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.black.opacity(0.6))
                        Rectangle().fill(Theme.accent)
                            .frame(width: geo.size.width * CGFloat(watched) / CGFloat(max(item.episodes.count, 1)))
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

struct ItemMenu: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    let item: LibraryItem

    var body: some View {
        Button(item.kind == .show ? "Play Next Episode" : "Play") { library.play(item) }
        Button(library.isWatched(item) ? "Mark as Unwatched" : "Mark as Watched") {
            library.setWatched(!library.isWatched(item), item: item)
        }
        Divider()
        Button("Fix Match…") { router.fixing = item }
        Button("Refresh Metadata") { library.refreshMetadata(item) }
        Button("Show in Finder") { library.reveal(item) }
    }
}
