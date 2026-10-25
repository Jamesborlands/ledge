import AppKit

@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var shelves: [Shelf] = []

    let rootURL: URL
    private var indexURL: URL { rootURL.appendingPathComponent("shelves.json") }
    private var contentRoot: URL { rootURL.appendingPathComponent("Content", isDirectory: true) }

    private init() {
        // LEDGE_STORE points screenshot runs at a scratch folder so they don't touch real shelves.
        if let dir = ProcessInfo.processInfo.environment["LEDGE_STORE"] {
            rootURL = URL(fileURLWithPath: dir, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            rootURL = support.appendingPathComponent("Ledge", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: rootURL.appendingPathComponent("Content"), withIntermediateDirectories: true)
        load()
    }

    /// Shelves with something on them, newest first.
    var history: [Shelf] {
        shelves.filter { !$0.items.isEmpty }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func shelf(_ id: UUID) -> Shelf? { shelves.first { $0.id == id } }

    func createShelf() -> UUID {
        let shelf = Shelf()
        shelves.insert(shelf, at: 0)
        return shelf.id
    }

    func contentDirectory(for id: UUID) -> URL {
        let dir = contentRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func isOwnedPath(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(contentRoot.standardizedFileURL.path + "/")
    }

    func add(_ newItems: [ShelfItem], to id: UUID) {
        guard !newItems.isEmpty else { return }
        mutate(id) { shelf in
            var seen = Set(shelf.items.map(\.path))
            for item in newItems where seen.insert(item.path).inserted {
                shelf.items.append(item)
            }
        }
    }

    func remove(_ ids: Set<UUID>, from id: UUID) {
        guard let shelf = shelf(id), !ids.isEmpty else { return }
        for item in shelf.items where ids.contains(item.id) && item.owned {
            try? FileManager.default.removeItem(at: item.url)
        }
        mutate(id) { $0.items.removeAll { ids.contains($0.id) } }
    }

    func clear(_ id: UUID) {
        guard let shelf = shelf(id) else { return }
        remove(Set(shelf.items.map(\.id)), from: id)
    }

    /// Re-finds referenced files that were moved or renamed since they were shelved.
    func resolveMissing(in id: UUID) {
        guard let i = shelves.firstIndex(where: { $0.id == id }) else { return }
        var shelf = shelves[i]
        for j in shelf.items.indices { shelf.items[j].resolveBookmark() }
        if shelf.items.map(\.path) != shelves[i].items.map(\.path) {
            shelves[i] = shelf
            save()
        }
    }

    /// Drops empty shelves that aren't on screen and trims history to the configured limit.
    func prune(keeping openIDs: Set<UUID>) {
        let empty = shelves.filter { $0.items.isEmpty && !openIDs.contains($0.id) }
        let stale = history.dropFirst(Settings.historyLimit).filter { !openIDs.contains($0.id) }
        discard(Set((empty + stale).map(\.id)))
    }

    func clearHistory(keeping openIDs: Set<UUID>) {
        discard(Set(shelves.map(\.id)).subtracting(openIDs))
    }

    private func discard(_ ids: Set<UUID>) {
        for id in ids {
            try? FileManager.default.removeItem(at: contentRoot.appendingPathComponent(id.uuidString))
        }
        shelves.removeAll { ids.contains($0.id) }
        save()
    }

    private func mutate(_ id: UUID, _ change: (inout Shelf) -> Void) {
        guard let i = shelves.firstIndex(where: { $0.id == id }) else { return }
        change(&shelves[i])
        shelves[i].updatedAt = Date()
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(shelves.filter { !$0.items.isEmpty })
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("Ledge: couldn't save shelves: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let loaded = try? JSONDecoder().decode([Shelf].self, from: data) else { return }
        shelves = loaded
    }
}
