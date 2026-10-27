import AppKit
import Quartz
import SwiftUI

/// Owns one floating shelf window and everything you can do with its items.
@MainActor
final class ShelfController: NSObject, ObservableObject, NSWindowDelegate {
    let shelfID: UUID
    let panel: ShelfPanel

    @Published var selection: Set<UUID> = []
    @Published private(set) var isDropTarget = false
    @Published var dropFlash = false
    /// Finder dims selections in windows that aren't key; the tiles follow this.
    @Published var isKey = false

    /// Matches the continuous corner radius of Tahoe's floating panels.
    static let cornerRadius: CGFloat = 20

    private let store = ShelfStore.shared
    private var keyMonitor: Any?
    private var draggingIDs: [UUID] = []
    private var previewItems: [ShelfItem] = []
    private let glass = NSGlassEffectView()
    private var isClosing = false

    init(shelfID: UUID) {
        self.shelfID = shelfID
        panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 272),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init()

        panel.controller = self
        panel.delegate = self
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 200, height: 170)
        panel.isOpaque = false
        panel.backgroundColor = .clear

        let host = ShelfHostingView(rootView: ShelfView(controller: self))
        host.controller = self
        host.sizingOptions = []
        // The window itself is the glass; everything inside sits on it without its own material.
        glass.cornerRadius = Self.cornerRadius
        glass.contentView = host
        panel.contentView = glass

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
        store.resolveMissing(in: shelfID)
    }

    var items: [ShelfItem] { store.shelf(shelfID)?.items ?? [] }
    var selectedItems: [ShelfItem] { items.filter { selection.contains($0.id) } }
    /// What toolbar actions apply to: the selection, or everything when nothing is selected.
    var targetItems: [ShelfItem] { selection.isEmpty ? items : selectedItems }

    // MARK: Window

    /// Places the shelf with its top edge centered under `point` (the notch), kept on screen.
    func showBelow(_ point: NSPoint) {
        let size = panel.frame.size
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height - 6)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
            origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - size.height - 8)
        }
        // Drop down out of the notch: start a little higher and transparent, then settle.
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + 14))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrameOrigin(origin)
            panel.animator().alphaValue = 1
        }
    }

    func bringToFront() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        guard !isClosing else { return }
        isClosing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.close() }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) { isKey = true }
    func windowDidResignKey(_ notification: Notification) { isKey = false }

    /// Tints the glass with the accent color while a drop is hovering, like a Finder drop target.
    func setDropTarget(_ active: Bool) {
        guard isDropTarget != active else { return }
        isDropTarget = active
        glass.tintColor = active ? NSColor.controlAccentColor.withAlphaComponent(0.22) : nil
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if QLPreviewPanel.sharedPreviewPanelExists(), let ql = QLPreviewPanel.shared(), ql.isVisible, ql.dataSource === self {
            ql.orderOut(nil)
        }
        AppDelegate.shared.shelfDidClose(shelfID)
    }

    // MARK: Adding

    @discardableResult
    func accept(_ pasteboard: NSPasteboard) -> Bool {
        let id = shelfID
        let promised = pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
        let newItems = Ingest.items(from: pasteboard, into: id) { late in
            ShelfStore.shared.add(late, to: id)
        }
        store.add(newItems, to: id)
        let accepted = !newItems.isEmpty || promised
        if accepted {
            dropFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.dropFlash = false }
        }
        return accepted
    }

    // MARK: Selection & keys

    /// Selects on mouse down like Finder. A plain click on an already selected item waits for
    /// mouse up, so dragging a multi-selection doesn't collapse it first.
    func mouseDown(on item: ShelfItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) || modifiers.contains(.shift) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        } else if !selection.contains(item.id) {
            selection = [item.id]
        }
    }

    func mouseUp(on item: ShelfItem, modifiers: NSEvent.ModifierFlags) {
        if !modifiers.contains(.command), !modifiers.contains(.shift) { selection = [item.id] }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            switch chars {
            case "a": selection = Set(items.map(\.id))
            case "c": copy(targetItems)
            case "v": accept(.general)
            case "w": close()
            case "o": open(targetItems)
            default: return false
            }
            return true
        }
        switch event.keyCode {
        case 49: quickLook() // space
        case 36, 76: open(selectedItems) // return
        case 51, 117: removeFromShelf(selectedItems) // delete
        case 53: if selection.isEmpty { close() } else { selection = [] } // esc
        default: return false
        }
        return true
    }

    // MARK: Dragging out

    func beginDrag(from tile: ItemTileView, item: ShelfItem, event: NSEvent) {
        let dragging = selection.contains(item.id) ? selectedItems : [item]
        beginDrag(dragging, from: tile, frame: tile.imageFrame, event: event)
    }

    func beginDrag(_ dragging: [ShelfItem], from view: NSView & NSDraggingSource, frame: NSRect, event: NSEvent) {
        let present = dragging.filter(\.exists)
        guard !present.isEmpty else { return }
        draggingIDs = present.map(\.id)
        let draggingItems = present.enumerated().map { index, item in
            let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let offset = CGFloat(min(index, 4)) * 4
            draggingItem.setDraggingFrame(frame.offsetBy(dx: offset, dy: -offset), contents: Thumbnails.shared.image(for: item.url))
            return draggingItem
        }
        let session = view.beginDraggingSession(with: draggingItems, event: event, source: view)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    func dragEnded(_ operation: NSDragOperation) {
        let ids = draggingIDs
        draggingIDs = []
        guard !operation.isEmpty else { return }
        // Files the destination moved away (e.g. Finder on the same disk) no longer belong on the shelf.
        var gone = Set(items.filter { ids.contains($0.id) && !$0.exists }.map(\.id))
        if Settings.removeAfterDrag { gone.formUnion(ids) }
        selection.subtract(gone)
        store.remove(gone, from: shelfID)
    }

    func isOwnDrag(_ info: NSDraggingInfo) -> Bool {
        (info.draggingSource as? ItemTileView)?.controller === self || (info.draggingSource as? DragAllView)?.controller === self
    }

    // MARK: Actions

    func open(_ targets: [ShelfItem]) {
        for item in targets where item.exists { NSWorkspace.shared.open(item.url) }
    }

    func reveal(_ targets: [ShelfItem]) {
        let urls = targets.filter(\.exists).map(\.url)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func copy(_ targets: [ShelfItem]) {
        let urls = targets.filter(\.exists).map { $0.url as NSURL }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls)
    }

    /// Where the header's actions button sits, in the hosting view's (flipped) coordinates.
    var actionsButtonFrame: NSRect = .zero

    func share(_ targets: [ShelfItem]) {
        guard let view = glass.contentView else { return }
        let urls = targets.filter(\.exists).map(\.url)
        guard !urls.isEmpty else { return }
        var anchor = actionsButtonFrame
        if anchor.isEmpty { anchor = NSRect(x: view.bounds.maxX - 64, y: 6, width: 26, height: 26) }
        NSSharingServicePicker(items: urls).show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }

    func saveToFolder(_ targets: [ShelfItem]) {
        let urls = targets.filter(\.exists).map(\.url)
        guard !urls.isEmpty else { return }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.canCreateDirectories = true
        picker.prompt = "Save Here"
        picker.message = "Choose where to save copies of \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items")"
        NSApp.activate(ignoringOtherApps: true)
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        var saved: [URL] = []
        for url in urls {
            let dest = Ingest.uniqueURL(in: folder, name: url.lastPathComponent)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { saved.append(dest) }
        }
        if saved.count < urls.count { NSSound.beep() }
        if !saved.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(saved) }
    }

    func compress(_ targets: [ShelfItem]) {
        let urls = targets.filter(\.exists).map(\.url)
        guard !urls.isEmpty else { return }
        let id = shelfID
        let name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Archive"
        let dest = Ingest.uniqueURL(in: store.contentDirectory(for: id), name: name + ".zip")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = ShelfController.zip(urls, to: dest)
            DispatchQueue.main.async {
                if ok { ShelfStore.shared.add([ShelfItem(url: dest, owned: true)], to: id) } else { NSSound.beep() }
            }
        }
    }

    nonisolated private static func zip(_ urls: [URL], to dest: URL) -> Bool {
        let fm = FileManager.default
        var source = urls[0]
        var staging: URL?
        if urls.count > 1 {
            let root = fm.temporaryDirectory.appendingPathComponent("Ledge-\(UUID().uuidString)")
            let folder = root.appendingPathComponent(dest.deletingPathExtension().lastPathComponent)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for url in urls {
                try? fm.copyItem(at: url, to: Ingest.uniqueURL(in: folder, name: url.lastPathComponent))
            }
            source = folder
            staging = root
        }
        defer { if let staging { try? fm.removeItem(at: staging) } }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--keepParent", source.path, dest.path]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func removeFromShelf(_ targets: [ShelfItem]) {
        let ids = Set(targets.map(\.id))
        selection.subtract(ids)
        store.remove(ids, from: shelfID)
    }

    func clear() {
        selection = []
        store.clear(shelfID)
    }

    func contextMenu(for item: ShelfItem) -> NSMenu {
        if !selection.contains(item.id) { selection = [item.id] }
        let targets = selectedItems
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Open", symbol: "arrow.up.forward.app") { [weak self] in self?.open(targets) })
        menu.addItem(ClosureMenuItem("Quick Look", symbol: "eye") { [weak self] in self?.quickLook() })
        menu.addItem(ClosureMenuItem("Show in Finder", symbol: "folder") { [weak self] in self?.reveal(targets) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Copy", symbol: "doc.on.doc") { [weak self] in self?.copy(targets) })
        menu.addItem(ClosureMenuItem("Share…", symbol: "square.and.arrow.up") { [weak self] in self?.share(targets) })
        menu.addItem(ClosureMenuItem("Save Copy To…", symbol: "square.and.arrow.down") { [weak self] in self?.saveToFolder(targets) })
        menu.addItem(ClosureMenuItem("Compress", symbol: "archivebox") { [weak self] in self?.compress(targets) })
        menu.addItem(.separator())
        let remove = targets.count > 1 ? "Remove \(targets.count) Items from Shelf" : "Remove from Shelf"
        menu.addItem(ClosureMenuItem(remove, symbol: "minus.circle") { [weak self] in self?.removeFromShelf(targets) })
        return menu
    }

    /// The header's ••• menu. Acts on the selection, or on everything when nothing is selected.
    func actionsMenu() -> NSMenu {
        let scope = selection.isEmpty ? "All" : "Selected"
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Open \(scope)", symbol: "arrow.up.forward.app") { [weak self] in
            guard let self else { return }
            self.open(self.targetItems)
        })
        menu.addItem(ClosureMenuItem("Quick Look", symbol: "eye") { [weak self] in self?.quickLook() })
        menu.addItem(ClosureMenuItem("Show in Finder", symbol: "folder") { [weak self] in
            guard let self else { return }
            self.reveal(self.targetItems)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Copy \(scope)", symbol: "doc.on.doc") { [weak self] in
            guard let self else { return }
            self.copy(self.targetItems)
        })
        menu.addItem(ClosureMenuItem("Share…", symbol: "square.and.arrow.up") { [weak self] in
            guard let self else { return }
            self.share(self.targetItems)
        })
        menu.addItem(ClosureMenuItem("Save Copies To…", symbol: "square.and.arrow.down") { [weak self] in
            guard let self else { return }
            self.saveToFolder(self.targetItems)
        })
        menu.addItem(ClosureMenuItem("Compress \(scope) to Zip", symbol: "archivebox") { [weak self] in
            guard let self else { return }
            self.compress(self.targetItems)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Select All", symbol: "checkmark.circle") { [weak self] in
            guard let self else { return }
            self.selection = Set(self.items.map(\.id))
        })
        if !selection.isEmpty {
            menu.addItem(ClosureMenuItem("Remove Selected", symbol: "minus.circle") { [weak self] in
                guard let self else { return }
                self.removeFromShelf(self.selectedItems)
            })
        }
        menu.addItem(ClosureMenuItem("Clear Shelf", symbol: "trash") { [weak self] in self?.clear() })
        menu.addItem(ClosureMenuItem("Close Shelf", symbol: "xmark") { [weak self] in self?.close() })
        return menu
    }

    func showActionsMenu() {
        guard let view = glass.contentView else { return }
        let frame = actionsButtonFrame
        let point = frame.isEmpty ? NSPoint(x: view.bounds.maxX - 60, y: 34) : NSPoint(x: frame.minX, y: frame.maxY + 6)
        actionsMenu().popUp(positioning: nil, at: point, in: view)
    }

    // MARK: Quick Look

    func quickLook() {
        guard let ql = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), ql.isVisible {
            ql.orderOut(nil)
            return
        }
        previewItems = (selection.isEmpty ? items : selectedItems).filter(\.exists)
        guard !previewItems.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        ql.updateController()
        ql.dataSource = self
        ql.reloadData()
        ql.makeKeyAndOrderFront(nil)
    }
}

extension ShelfController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { previewItems.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { previewItems[index].url as NSURL }
    }
}

final class ShelfPanel: NSPanel {
    weak var controller: ShelfController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = controller
        panel.delegate = controller
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

/// Hosts the SwiftUI shelf and accepts anything dropped onto it.
final class ShelfHostingView: NSHostingView<ShelfView> {
    weak var controller: ShelfController?

    required init(rootView: ShelfView) {
        super.init(rootView: rootView)
        registerForDraggedTypes(Ingest.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let controller, !controller.isOwnDrag(sender) else { return [] }
        controller.setDropTarget(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let controller, !controller.isOwnDrag(sender) else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        controller?.setDropTarget(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        controller?.setDropTarget(false)
        return controller?.accept(sender.draggingPasteboard) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        controller?.setDropTarget(false)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
         handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
