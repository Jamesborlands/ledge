import AppKit
import QuickLookThumbnailing

@MainActor
final class Thumbnails {
    static let shared = Thumbnails()

    private let cache = NSCache<NSString, NSImage>()

    /// Best image available right now: a cached preview, else the Finder icon.
    func image(for url: URL) -> NSImage {
        cache.object(forKey: url.path as NSString) ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Generates a real preview (photos, PDFs, documents) and calls back on the main thread.
    func load(_ url: URL, completion: @escaping (NSImage) -> Void) {
        let path = url.path
        if let cached = cache.object(forKey: path as NSString) {
            completion(cached)
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 160, height: 160), scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async {
                self.cache.setObject(image, forKey: path as NSString)
                completion(image)
            }
        }
    }
}
