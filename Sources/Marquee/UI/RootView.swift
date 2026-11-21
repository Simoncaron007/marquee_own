import SwiftUI

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            Group {
                if !library.isConfigured {
                    WelcomeView()
                } else if let id = router.openItemID, let item = library.item(id: id) {
                    DetailView(item: item).id(item.id)
                } else if !router.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchResultsView(query: router.query)
                } else {
                    switch router.section {
                    case .home: HomeView()
                    case .movies: LibraryGridView(kind: .movie)
                    case .shows: LibraryGridView(kind: .show)
                    case .history: HistoryView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TopBar()
        }
        .ignoresSafeArea()
        .sheet(item: $router.fixing) { item in
            FixMatchView(item: item)
                .environment(library)
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var router = router
        HStack(spacing: 22) {
            Color.clear.frame(width: 62, height: 1)  // room for the traffic lights

            if router.openItemID != nil {
                Button {
                    router.openItemID = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Back")
            }

            Text("Marquee")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.accent)

            if library.isConfigured {
                ForEach(LibrarySection.allCases) { section in
                    let active = router.section == section && router.openItemID == nil && router.query.isEmpty
                    Button(section.rawValue) { router.go(section) }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? Color.white : Theme.secondary)
                }
            }

            Spacer(minLength: 12)

            status

            if library.isConfigured {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
                    TextField("Titles, people…", text: $router.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onChange(of: router.query) { _, newValue in
                            if !newValue.isEmpty { router.openItemID = nil }
                        }
                    if !router.query.isEmpty {
                        Button { router.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 230)
                .background(Color.white.opacity(0.09), in: Capsule())
                .background {
                    Button("") { searchFocused = true }
                        .keyboardShortcut("f")
                        .opacity(0)
                }

                Button { library.rescan() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .help("Rescan library folder")
            }

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 18)
        .frame(height: Theme.topBarHeight)
        .background { WindowDragArea() }
        .background(alignment: .top) {
            LinearGradient(colors: [Theme.background.opacity(0.94), Theme.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Theme.topBarHeight + 34)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var status: some View {
        if let error = library.errorMessage {
            Button {
                library.errorMessage = nil
            } label: {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.orange)
            .help("Click to dismiss")
        } else if let progress = library.matchProgress {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Identifying \(progress.done) of \(progress.total)")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.tertiary)
        } else if library.isScanning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning…")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.tertiary)
        }
    }
}

// MARK: - First run

struct WelcomeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Marquee")
                    .font(.system(size: 34, weight: .bold))
                Text("Two quick steps and your downloads folder becomes a library.")
                    .foregroundStyle(Theme.secondary)
            }

            step(1, done: !library.apiKey.isEmpty, title: "Add a free TMDB key",
                 detail: "Artwork, plots and cast come from The Movie Database. Create a free account, then copy the “API Key” (or the “API Read Access Token”).") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Paste your TMDB key", text: $library.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 380)
                    Link("Get a key at themoviedb.org →", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                }
            }

            step(2, done: library.rootPath != nil, title: "Choose your media folder",
                 detail: library.rootPath ?? "The folder with your movies and shows, e.g. Documents/BiglyBT Downloads. Marquee only reads it — nothing gets moved or renamed.") {
                Button(library.rootPath == nil ? "Choose Folder…" : "Change Folder…") { library.chooseFolder() }
                    .buttonStyle(PillButtonStyle(prominent: library.rootPath == nil))
            }
        }
        .padding(44)
        .frame(width: 620, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.hairline))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step<Content: View>(_ n: Int, done: Bool, title: String, detail: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(done ? Theme.accent : Color.white.opacity(0.1))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                } else {
                    Text("\(n)").font(.system(size: 13, weight: .bold))
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
        }
    }
}
