import AppKit
import SwiftUI

/// One file on the shelf: thumbnail + name. AppKit so dragging out behaves exactly like Finder.
/// Selection looks like Finder's icon view on Tahoe: a soft plate behind the thumbnail and an
/// accent pill behind the name (gray when the shelf isn't key).
final class ItemTileView: NSView, NSDraggingSource {
    weak var controller: ShelfController?
    private(set) var item: ShelfItem?

    private let plate = NSView()
    private let imageView = NSImageView()
    private let labelPill = NSView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private var mouseDownEvent: NSEvent?
    private var loadedPath: String?
    private var selected = false
    private var emphasized = true
    private var hovering = false

    init(controller: ShelfController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true

        for view in [plate, labelPill] {
            view.wantsLayer = true
            view.layer?.cornerCurve = .continuous
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        plate.layer?.cornerRadius = 10
        labelPill.layer?.cornerRadius = 5

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
        // Like Finder: wrap onto a second line, then truncate.
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.cell?.truncatesLastVisibleLine = true
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(plate)
        addSubview(imageView)
        addSubview(labelPill)
        addSubview(label)
        NSLayoutConstraint.activate([
            plate.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            plate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            plate.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            // Fixed room for two lines of name keeps thumbnails aligned across a row.
            plate.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -32),
            imageView.topAnchor.constraint(equalTo: plate.topAnchor, constant: 5),
            imageView.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: 5),
            imageView.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -5),
            imageView.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -5),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: plate.bottomAnchor, constant: 3),
            labelPill.topAnchor.constraint(equalTo: label.topAnchor, constant: -1),
            labelPill.bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: 1),
            labelPill.leadingAnchor.constraint(equalTo: label.leadingAnchor, constant: -5),
            labelPill.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: 5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var imageFrame: NSRect { imageView.frame }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

    override func layout() {
        label.preferredMaxLayoutWidth = max(0, bounds.width - 16)
        super.layout()
    }

    func configure(item: ShelfItem, selected: Bool, emphasized: Bool) {
        self.item = item
        self.selected = selected
        self.emphasized = emphasized
        label.stringValue = item.name
        toolTip = item.exists ? item.path : "\(item.path)\n(missing: moved or deleted)"
        alphaValue = item.exists ? 1 : 0.4
        updateColors()

        guard loadedPath != item.path else { return }
        loadedPath = item.path
        let path = item.path
        imageView.image = Thumbnails.shared.image(for: item.url)
        Thumbnails.shared.load(item.url) { [weak self] image in
            guard let self, self.item?.path == path else { return }
            self.imageView.image = image
        }
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let plateAlpha: CGFloat = selected ? 0.11 : hovering ? 0.055 : 0
            plate.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(plateAlpha).cgColor
            let pill: NSColor = !selected ? .clear : emphasized ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor
            labelPill.layer?.backgroundColor = pill.cgColor
        }
        label.textColor = selected && emphasized ? .alternateSelectedControlTextColor : .labelColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    private func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.allowsImplicitAnimation = true
            updateColors()
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The whole tile takes the click, so the plate's margins never start a window drag.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let item, let controller else { return }
        if event.clickCount == 2 {
            controller.open([item])
            mouseDownEvent = nil
            return
        }
        controller.mouseDown(on: item, modifiers: event.modifierFlags)
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
            controller?.mouseUp(on: item, modifiers: down.modifierFlags)
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
            let slot = NSRect(x: offset, y: 2 + CGFloat(2 - index) * 1.5, width: side, height: side)
            let image = Thumbnails.shared.image(for: item.url)
            // Aspect-fit so documents and photos keep their shape in the stack.
            let scale = min(slot.width / max(image.size.width, 1), slot.height / max(image.size.height, 1))
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = NSRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).addClip()
            image.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
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
    let emphasized: Bool
    let controller: ShelfController

    func makeNSView(context: Context) -> ItemTileView { ItemTileView(controller: controller) }

    func updateNSView(_ view: ItemTileView, context: Context) {
        view.configure(item: item, selected: selected, emphasized: emphasized)
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
