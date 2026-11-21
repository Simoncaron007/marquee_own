import AppKit

/// Opens files in IINA (falls back to the default app if IINA isn't installed).
enum Player {
    static let iinaBundleID = "com.colliderli.iina"

    static var iinaURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: iinaBundleID)
    }

    static func open(_ file: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let iina = iinaURL {
            NSWorkspace.shared.open([file], withApplicationAt: iina, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(file)
        }
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
