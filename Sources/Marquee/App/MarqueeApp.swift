import SwiftUI

@main
struct MarqueeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = Library()
    @State private var router = Router()

    var body: some Scene {
        Window("Marquee", id: "main") {
            RootView()
                .environment(library)
                .environment(router)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(.dark)
                .task { library.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Library Folder…") { library.chooseFolder() }
                    .keyboardShortcut("o")
                Button("Rescan Library") { library.rescan() }
                    .keyboardShortcut("r")
            }
            CommandGroup(after: .toolbar) {
                Button("Home") { router.go(.home) }.keyboardShortcut("1")
                Button("Movies") { router.go(.movies) }.keyboardShortcut("2")
                Button("TV Shows") { router.go(.shows) }.keyboardShortcut("3")
                Button("History") { router.go(.history) }.keyboardShortcut("4")
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case home = "Home", movies = "Movies", shows = "TV Shows", history = "History"
    var id: String { rawValue }
}

/// Navigation state: which tab, which title is open, what's being searched.
@MainActor
@Observable
final class Router {
    var section: LibrarySection = .home
    var query = ""
    var openItemID: String?
    var fixing: LibraryItem?

    func go(_ section: LibrarySection) {
        self.section = section
        openItemID = nil
        query = ""
    }

    func open(_ item: LibraryItem) { openItemID = item.id }

    func searchPerson(_ name: String) {
        openItemID = nil
        query = name
    }
}
