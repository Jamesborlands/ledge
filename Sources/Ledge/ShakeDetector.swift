import AppKit

/// Watches drags system-wide: a quick left-right shake, or carrying the file up to the notch, opens a shelf.
/// Polls the cursor while the button is held, so it works no matter which app owns the drag.
@MainActor
final class ShakeDetector {
    var onShake: (() -> Void)?
    /// Called with the notch (or top-center) area the drag reached.
    var onNotch: ((NSRect) -> Void)?

    private let glow = NotchGlow()
    private var monitors: [Any] = []
    private var timer: Timer?
    private var samples: [(time: TimeInterval, x: CGFloat)] = []
    private var dragChangeCount = 0
    private var fired = false

    func start() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.beginTracking()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            self?.beginTracking()
            return event
        }) {
            monitors.append(local)
        }
    }

    private func beginTracking() {
        guard Settings.shakeEnabled || Settings.notchEnabled else { return }
        timer?.invalidate()
        samples = []
        fired = false
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            timer?.invalidate()
            timer = nil
            glow.hide()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        samples.append((now, NSEvent.mouseLocation.x))
        samples.removeAll { now - $0.time > 0.8 }

        // Only a real drag-and-drop writes to the drag pasteboard; selecting text or moving windows doesn't.
        guard !fired, NSPasteboard(name: .drag).changeCount != dragChangeCount else { return }
        let mouse = NSEvent.mouseLocation
        if Settings.notchEnabled, let zone = Self.notchZone(at: mouse) {
            let target = zone.insetBy(dx: -24, dy: -16)
            if target.contains(mouse) {
                fired = true
                glow.flare()
                onNotch?(zone)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.glow.hide() }
                return
            }
            // Brighten as the drag closes in, so it's obvious where to go.
            let dx = max(target.minX - mouse.x, 0, mouse.x - target.maxX)
            let dy = max(target.minY - mouse.y, 0, mouse.y - target.maxY)
            let distance = hypot(dx, dy)
            if distance < Self.glowRange {
                glow.update(proximity: 1 - distance / Self.glowRange, zone: zone)
            } else {
                glow.hide()
            }
        }
        guard Settings.shakeEnabled, isShake() else { return }
        fired = true
        samples = []
        onShake?()
    }

    private static let glowRange: CGFloat = 280

    /// The notch on MacBook displays, or a 200pt-wide top-center strip of the menu bar on other screens.
    static func notchZone(at point: NSPoint) -> NSRect? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return nil }
        return notchZone(on: screen)
    }

    /// The display with a notch (the built-in one), else the main display.
    static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main
    }

    static func notchZone(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let height = max(screen.safeAreaInsets.top, frame.maxY - screen.visibleFrame.maxY, 24)
        var minX = frame.midX - 100, maxX = frame.midX + 100
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // These areas are reported relative to the screen; the gap between them is the notch.
            let offset = left.minX == frame.minX ? 0 : frame.minX
            minX = left.maxX + offset
            maxX = right.minX + offset
        }
        return NSRect(x: minX, y: frame.maxY - height, width: maxX - minX, height: height)
    }

    private func isShake() -> Bool {
        let (needed, travel) = Settings.shakeThresholds
        guard let first = samples.first?.x else { return false }
        var direction = 0
        var low = first, high = first, extreme = first
        var reversals = 0
        for (_, x) in samples.dropFirst() {
            switch direction {
            case 0:
                low = min(low, x); high = max(high, x)
                if x - low >= travel { direction = 1; extreme = x }
                else if high - x >= travel { direction = -1; extreme = x }
            case 1:
                if x > extreme { extreme = x }
                else if extreme - x >= travel { reversals += 1; direction = -1; extreme = x }
            default:
                if x < extreme { extreme = x }
                else if x - extreme >= travel { reversals += 1; direction = 1; extreme = x }
            }
        }
        return reversals >= needed
    }
}
