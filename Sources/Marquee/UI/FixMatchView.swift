import SwiftUI

struct FixMatchView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem

    @State private var query: String
    @State private var year: String
    @State private var results: [TMDBSearchResult] = []
    @State private var searching = false
    @State private var error: String?

    init(item: LibraryItem) {
        self.item = item
        _query = State(initialValue: item.title)
        _year = State(initialValue: item.year.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fix Match").font(.system(size: 20, weight: .bold))
                Text("\(item.kind == .movie ? "Movie" : "TV show") · \(item.folders.first?.lastPathComponent ?? "")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                TextField("Title", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                TextField("Year", text: $year)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .onSubmit(search)
                Button("Search", action: search)
                    .keyboardShortcut(.defaultAction)
            }

            ZStack {
                List(results) { result in
                    HStack(alignment: .top, spacing: 12) {
                        TMDBImage(path: result.posterPath, size: "w185", placeholderSymbol: "photo")
                            .frame(width: 46, height: 69)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.displayTitle + (result.year.map { " (\($0))" } ?? ""))
                                .font(.system(size: 13, weight: .semibold))
                            Text(result.overview ?? "")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        Spacer()
                        Button("Choose") {
                            library.applyMatch(result, to: item)
                            dismiss()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)

                if searching {
                    ProgressView()
                } else if let error {
                    Text(error).foregroundStyle(.orange)
                } else if results.isEmpty {
                    Text("No results. Try the original title, or remove the year.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 320)

            HStack {
                Text("Tip: if this is really a \(item.kind == .movie ? "TV show" : "movie"), move it into a “\(item.kind == .movie ? "TV Shows" : "Movies")” subfolder of your library.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 600, height: 540)
        .task { search() }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        error = nil
        Task {
            do {
                results = try await library.searchTMDB(q, year: Int(year.trimmingCharacters(in: .whitespaces)), kind: item.kind)
            } catch {
                self.error = error.localizedDescription
                results = []
            }
            searching = false
        }
    }
}
