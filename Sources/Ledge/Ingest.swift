import AppKit

/// Turns whatever is on a pasteboard (a drop or the clipboard) into shelf items.
/// Files are referenced in place; text, links and images are saved into Ledge's storage.
@MainActor
enum Ingest {
    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .string, .png, .tiff, .pdf, .rtf]
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// Returns items available right away. Promised files (from Mail, Photos, etc.) arrive later via `onPromised`.
    static func items(from pb: NSPasteboard, into shelfID: UUID, onPromised: @escaping ([ShelfItem]) -> Void) -> [ShelfItem] {
        let store = ShelfStore.shared
        let dir = store.contentDirectory(for: shelfID)

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.compactMap { url in
                guard store.isOwnedPath(url) else { return ShelfItem(url: url, owned: false) }
                // Files Ledge owns get their own copy so each shelf can clean up independently.
                let dest = uniqueURL(in: dir, name: url.lastPathComponent)
                guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return nil }
                return ShelfItem(url: dest, owned: true)
            }
        }

        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: promiseQueue) { url, error in
                    guard error == nil else { return }
                    DispatchQueue.main.async { onPromised([ShelfItem(url: url, owned: true)]) }
                }
            }
            return []
        }

        if let links = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
            let web = links.filter { $0.scheme != nil && $0.host != nil && !$0.isFileURL }
            if !web.isEmpty {
                let name = pb.string(forType: NSPasteboard.PasteboardType("public.url-name"))
                return web.compactMap { saveLink($0, title: web.count == 1 ? name : nil, in: dir) }
            }
        }

        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
               ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                return saveLink(url, title: nil, in: dir).map { [$0] } ?? []
            }
            return saveText(text, in: dir).map { [$0] } ?? []
        }

        if let image = saveImage(from: pb, in: dir) {
            return [image]
        }

        return []
    }

    private static func saveLink(_ url: URL, title: String?, in dir: URL) -> ShelfItem? {
        let base = (title?.isEmpty == false ? title! : url.host ?? "Link")
        let dest = uniqueURL(in: dir, name: fileSafe(base) + ".webloc")
        guard let data = try? PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0),
              (try? data.write(to: dest)) != nil else { return nil }
        return ShelfItem(url: dest, owned: true)
    }

    private static func saveText(_ text: String, in dir: URL) -> ShelfItem? {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Text"
        let dest = uniqueURL(in: dir, name: fileSafe(String(firstLine.prefix(40))) + ".txt")
        guard (try? text.write(to: dest, atomically: true, encoding: .utf8)) != nil else { return nil }
        return ShelfItem(url: dest, owned: true)
    }

    private static func saveImage(from pb: NSPasteboard, in dir: URL) -> ShelfItem? {
        let data: Data?
        if let png = pb.data(forType: .png) {
            data = png
        } else if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation {
            data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        } else {
            data = nil
        }
        guard let data else { return nil }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let dest = uniqueURL(in: dir, name: fileSafe("Image \(stamp)") + ".png")
        guard (try? data.write(to: dest)) != nil else { return nil }
        return ShelfItem(url: dest, owned: true)
    }

    private static func fileSafe(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    nonisolated static func uniqueURL(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let numbered = "\(stem) \(n)"
            candidate = dir.appendingPathComponent(ext.isEmpty ? numbered : "\(numbered).\(ext)")
            n += 1
        }
        return candidate
    }
}
