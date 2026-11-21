import AppKit

/// Downloads TMDB artwork once and keeps it on disk (~/Library/Caches/Marquee/Images) and in memory.
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private func cacheKey(_ path: String, _ size: String) -> String { size + path }

    func cached(path: String, size: String) -> NSImage? {
        memory.object(forKey: cacheKey(path, size) as NSString)
    }

    func image(path: String, size: String) async -> NSImage? {
        let key = cacheKey(path, size)
        if let image = memory.object(forKey: key as NSString) { return image }
        if let task = inFlight[key] { return await task.value }

        let file = AppPaths.images.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_"))
        let task = Task<NSImage?, Never> {
            if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
                return image
            }
            guard let url = URL(string: "https://image.tmdb.org/t/p/\(size)\(path)"),
                  let result = try? await URLSession.shared.data(from: url),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: result.0) else { return nil }
            try? result.0.write(to: file, options: .atomic)
            return image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }
}
