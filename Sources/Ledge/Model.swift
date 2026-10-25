import Foundation

struct ShelfItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var path: String
    /// Lets us follow a referenced file if it's moved or renamed while it sits on a shelf.
    var bookmark: Data?
    /// True when the file lives in Ledge's own storage (pasted text, images, links, zips).
    var owned: Bool
    var addedAt = Date()

    init(url: URL, owned: Bool) {
        path = url.path
        self.owned = owned
        if !owned {
            bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    mutating func resolveBookmark() {
        guard !owned, !exists, let bookmark else { return }
        var stale = false
        if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
            path = resolved.path
        }
    }
}

struct Shelf: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var items: [ShelfItem] = []

    var title: String {
        guard let first = items.first else { return "Empty Shelf" }
        return items.count == 1 ? first.name : "\(items.count) Items"
    }

    var menuTitle: String {
        guard let first = items.first else { return "Empty Shelf" }
        let name = first.name.middleTruncated(to: 34)
        return items.count == 1 ? name : "\(name) + \(items.count - 1) more"
    }
}

extension String {
    func middleTruncated(to length: Int) -> String {
        guard count > length else { return self }
        let half = (length - 1) / 2
        return prefix(half) + "…" + suffix(length - 1 - half)
    }
}
