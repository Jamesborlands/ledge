import AppKit
import SwiftUI

/// One file on the shelf: thumbnail + name. AppKit so dragging out behaves exactly like Finder.
final class ItemTileView: NSView, NSDraggingSource {
    weak var controller: ShelfController?
    private(set) var item: ShelfItem?

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var mouseDownEvent: NSEvent?
    private var loadedPath: String?

    init(controller: ShelfController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.unregisterDraggedTypes()
        // Previews can be large; never let their natural size push the tile bigger than the grid cell.
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            imageView.setContentCompressionResistancePriority(.init(1), for: axis)
            imageView.setContentHuggingPriority(.init(1), for: axis)
        }

        label.font = .systemFont(ofSize: 11)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        label.cell?.truncatesLastVisibleLine = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(imageView)
        addSubview(label)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            imageView.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var imageFrame: NSRect { imageView.frame }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

    func configure(item: ShelfItem, selected: Bool) {
        self.item = item
        label.stringValue = item.name
        toolTip = item.exists ? item.path : "\(item.path)\n(missing — moved or deleted)"
        alphaValue = item.exists ? 1 : 0.4
        layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor : NSColor.clear.cgColor
        label.textColor = selected ? .labelColor : .secondaryLabelColor

        guard loadedPath != item.path else { return }
        loadedPath = item.path
        let path = item.path
        imageView.image = Thumbnails.shared.image(for: item.url)
        Thumbnails.shared.load(item.url) { [weak self] image in
            guard let self, self.item?.path == path else { return }
            self.imageView.image = image
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let item, let controller else { return }
        if event.clickCount == 2 {
            controller.open([item])
            mouseDownEvent = nil
            return
        }
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, let item, let controller else { return }
        let start = down.locationInWindow, now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        mouseDownEvent = nil
        controller.beginDrag(from: self, item: item, event: down)
    }

    override func mouseUp(with event: NSEvent) {
        if let down = mouseDownEvent, let item {
            controller?.click(item, modifiers: down.modifierFlags)
        }
        mouseDownEvent = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let item, let controller else { return nil }
        return controller.contextMenu(for: item)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        controller?.dragEnded(operation)
    }
}

/// The stacked-icon handle in the header that drags every item at once.
final class DragAllView: NSView, NSDraggingSource {
    weak var controller: ShelfController?
    private var mouseDownEvent: NSEvent?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let items = controller?.items, !items.isEmpty else {
            let tint = NSImage.SymbolConfiguration(paletteColors: [.tertiaryLabelColor])
            let symbol = NSImage(systemSymbolName: "tray", accessibilityDescription: nil)?.withSymbolConfiguration(tint)
            symbol?.draw(in: bounds.insetBy(dx: 7, dy: 6))
            return
        }
        let side = bounds.height - 4
        for (index, item) in items.prefix(3).enumerated().reversed() {
            let offset = CGFloat(index) * 4
            let rect = NSRect(x: offset, y: 2 + CGFloat(2 - index) * 1.5, width: side, height: side)
            Thumbnails.shared.image(for: item.url).draw(in: rect)
        }
    }

    override func mouseDown(with event: NSEvent) { mouseDownEvent = event }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, let controller, !controller.items.isEmpty else { return }
        mouseDownEvent = nil
        let side = bounds.height - 4
        controller.beginDrag(controller.items, from: self, frame: NSRect(x: 0, y: 2, width: side, height: side), event: down)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        controller?.dragEnded(operation)
    }
}

struct TileRepresentable: NSViewRepresentable {
    let item: ShelfItem
    let selected: Bool
    let controller: ShelfController

    func makeNSView(context: Context) -> ItemTileView { ItemTileView(controller: controller) }

    func updateNSView(_ view: ItemTileView, context: Context) {
        view.configure(item: item, selected: selected)
    }
}

struct DragAllRepresentable: NSViewRepresentable {
    let controller: ShelfController
    let itemPaths: [String]

    func makeNSView(context: Context) -> DragAllView {
        let view = DragAllView()
        view.controller = controller
        view.toolTip = "Drag to move everything on this shelf"
        return view
    }

    func updateNSView(_ view: DragAllView, context: Context) {
        view.needsDisplay = true
    }
}

/// Lets the header move the window even though it sits on top of SwiftUI content.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
