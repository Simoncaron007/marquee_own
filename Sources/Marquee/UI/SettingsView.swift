import SwiftUI

struct SettingsView: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        Form {
            Section("Library") {
                LabeledContent("Folder") {
                    HStack {
                        Text(library.rootPath ?? "Not set")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…") { library.chooseFolder() }
                    }
                }
                Toggle("Mark as watched when I press Play", isOn: $library.markWatchedOnPlay)
                Text("Turn this off to tick episodes and movies off by hand instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Metadata") {
                SecureField("TMDB API key or Read Access Token", text: $library.apiKey)
                Link("Get a free key at themoviedb.org", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                    .font(.caption)
                Picker("Language", selection: $library.language) {
                    ForEach(Library.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                Button("Re-download All Metadata") { library.matchMissing(refresh: true) }
                Text("Use this after changing the language. Your watch history is kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Playback") {
                LabeledContent("Player") {
                    Text(Player.iinaURL != nil ? "IINA" : "IINA not found — using each file’s default app")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 480)
    }
}
