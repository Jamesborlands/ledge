import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var shared: AppDelegate!

    private var controllers: [UUID: ShelfController] = [:]
    private let statusMenu = StatusMenuController()
    private let shake = ShakeDetector()
    private var settingsWindow: NSWindow?

    var openShelfIDs: Set<UUID> { Set(controllers.keys) }

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.register()
        ShelfStore.shared.prune(keeping: [])
        statusMenu.install()

        let mods = optionKey | shiftKey
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_D, modifiers: mods) { [weak self] in self?.newShelf() }
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_V, modifiers: mods) { [weak self] in self?.newShelfFromClipboard() }

        shake.onShake = { [weak self] in self?.newShelf() }
        shake.onNotch = { [weak self] _ in self?.newShelf() }
        shake.start()

        if !Settings.didFirstLaunch {
            Settings.didFirstLaunch = true
            _ = LoginItem.set(true)
        }

        handleTestArguments()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        newShelf()
        return false
    }

    /// Every shelf opens just under the notch; extra shelves step down so they don't stack exactly.
    @discardableResult
    func newShelf() -> ShelfController {
        present(ShelfStore.shared.createShelf())
    }

    private var notchAnchor: NSPoint {
        guard let screen = ShakeDetector.notchScreen else { return NSEvent.mouseLocation }
        let zone = ShakeDetector.notchZone(on: screen)
        let step = CGFloat(max(controllers.count, 0) % 5) * 28
        return NSPoint(x: zone.midX + step, y: zone.minY - step)
    }

    func newShelfFromClipboard() {
        let controller = newShelf()
        if !controller.accept(.general) {
            controller.close()
            NSSound.beep()
        }
    }

    func openShelf(_ id: UUID) {
        if let existing = controllers[id] {
            existing.bringToFront()
        } else {
            present(id)
        }
    }

    @discardableResult
    private func present(_ id: UUID) -> ShelfController {
        let anchor = notchAnchor
        let controller = ShelfController(shelfID: id)
        controllers[id] = controller
        controller.showBelow(anchor)
        return controller
    }

    func shelfDidClose(_ id: UUID) {
        controllers[id] = nil
        ShelfStore.shared.prune(keeping: openShelfIDs)
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Ledge Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Drag a file up to the notch, or press ⌥⇧D, to open a shelf.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }

    /// Test flags (launch with `open`, see scripts/snapshots.sh): `--shelf <file>...` opens a shelf holding
    /// those files, `--select` selects its first item, `--drop-target` shows the drop highlight, `--settings`
    /// opens Settings, `--appearance light|dark` forces one. `--stage` puts a plain backdrop behind everything
    /// (so screenshots show nothing personal), `--glow` holds the notch glow, and `--rect-out file` writes the
    /// rect to screenshot as `x,y,w,h` for `screencapture -R`. `--settings-snapshot`/`--glow-snapshot out.png`
    /// render those views straight to a PNG.
    private func handleTestArguments() {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let look = value("--appearance") {
            NSApp.appearance = NSAppearance(named: look == "light" ? .aqua : .darkAqua)
        }
        let staged = args.contains("--stage")
        if staged { showStage() }
        if args.contains("--clipboard") { newShelfFromClipboard() }
        if args.contains("--settings") || value("--settings-snapshot") != nil {
            showSettings()
            if staged, let window = settingsWindow, let screen = stageWindow?.screen {
                window.level = .statusBar + 2
                window.setFrameOrigin(NSPoint(x: screen.frame.midX - window.frame.width / 2,
                                              y: screen.visibleFrame.midY - window.frame.height / 2))
            }
        }
        if let out = value("--settings-snapshot") {
            Self.snapshot(after: 1.5, settingsWindow?.contentView, to: URL(fileURLWithPath: out)) {}
        }
        if let i = args.firstIndex(of: "--glow-snapshot"), i + 1 < args.count, let screen = ShakeDetector.notchScreen {
            let glow = NotchGlow()
            glow.update(proximity: 1, zone: ShakeDetector.notchZone(on: screen))
            if args.contains("--flare") { glow.flare() }
            Self.snapshot(after: 1.2, glow.contentView, to: URL(fileURLWithPath: args[i + 1])) { _ = glow }
        }
        if args.contains("--glow"), let screen = ShakeDetector.notchScreen {
            let glow = NotchGlow()
            glow.update(proximity: 1, zone: ShakeDetector.notchZone(on: screen))
            glow.flare()
            heldGlow = glow
        }
        if args.contains("--print-notch") {
            let screen = NSScreen.screens[0]
            print("notch zone:", ShakeDetector.notchZone(at: NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 1)) ?? .zero,
                  "screen:", screen.frame, "left:", screen.auxiliaryTopLeftArea ?? .zero, "right:", screen.auxiliaryTopRightArea ?? .zero)
            fflush(stdout)
        }
        var shelf: ShelfController?
        if let index = args.firstIndex(of: "--shelf") {
            let paths = args[(index + 1)...].prefix { !$0.hasPrefix("--") }
            let controller = newShelf()
            ShelfStore.shared.add(paths.map { ShelfItem(url: URL(fileURLWithPath: $0), owned: false) }, to: controller.shelfID)
            if staged {
                // Sit lower than usual so the glow under the notch stays in frame.
                controller.panel.level = .statusBar + 2
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let origin = controller.panel.frame.origin
                    controller.panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 90))
                }
            }
            if args.contains("--drop-target") { controller.setDropTarget(true) }
            if args.contains("--select"), let first = controller.items.first {
                controller.selection = [first.id]
                controller.bringToFront()
            }
            shelf = controller
        }
        if let out = value("--rect-out") {
            // After the shelf has settled, write the area worth capturing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let rect = self.captureRect(shelf: shelf) else { return }
                let top = NSScreen.screens[0].frame.maxY - rect.maxY
                let text = [rect.minX, top, rect.width, rect.height].map { String(Int($0.rounded())) }.joined(separator: ",")
                try? text.write(toFile: out, atomically: true, encoding: .utf8)
            }
        }
    }

    private var stageWindow: NSWindow?
    private var heldGlow: NotchGlow?

    /// A plain backdrop over the notch screen, menu bar included, so screenshots show only Ledge.
    private func showStage() {
        guard let screen = ShakeDetector.notchScreen ?? NSScreen.main else { return }
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: StageBackdrop(menuBarHeight: menuBar))
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        stageWindow = window
    }

    /// The hero framing (notch plus shelf) when the glow is up, else the shelf or Settings with room for the shadow.
    private func captureRect(shelf: ShelfController?) -> NSRect? {
        let margin: CGFloat = 56
        let rect: NSRect?
        if let shelf {
            let frame = shelf.panel.frame
            if heldGlow != nil, let screen = ShakeDetector.notchScreen {
                let midX = ShakeDetector.notchZone(on: screen).midX
                rect = NSRect(x: midX - 450, y: frame.minY - margin, width: 900, height: screen.frame.maxY - frame.minY + margin)
            } else {
                rect = frame.insetBy(dx: -margin, dy: -margin)
            }
        } else {
            rect = settingsWindow?.frame.insetBy(dx: -margin, dy: -margin)
        }
        // Never reach past the backdrop.
        guard let rect, let stage = stageWindow?.frame else { return rect }
        return rect.intersection(stage)
    }

    private static func snapshot(after delay: TimeInterval, _ view: NSView?, to url: URL, keepAlive: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            keepAlive()
            guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

/// Backdrop for screenshots: a dark wallpaper-like gradient (light in light mode) under a menu bar strip.
struct StageBackdrop: View {
    let menuBarHeight: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack(alignment: .top) {
            LinearGradient(colors: dark ? [Color(red: 0.09, green: 0.08, blue: 0.2), Color(red: 0.13, green: 0.23, blue: 0.42)]
                                        : [Color(red: 0.92, green: 0.88, blue: 0.96), Color(red: 0.76, green: 0.84, blue: 0.94)],
                           startPoint: .top, endPoint: .bottom)
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Circle().fill(dark ? Color(red: 0.47, green: 0.27, blue: 0.78) : Color(red: 1, green: 0.6, blue: 0.5))
                        .frame(width: size.width * 0.35).position(x: size.width * 0.36, y: size.height * 0.62)
                    Circle().fill(dark ? Color(red: 0.16, green: 0.55, blue: 0.86) : Color(red: 0.47, green: 0.74, blue: 1))
                        .frame(width: size.width * 0.3).position(x: size.width * 0.66, y: size.height * 0.3)
                }
                .blur(radius: 120)
                .opacity(0.7)
            }
            Rectangle().fill(dark ? Color(white: 0.05) : Color(white: 0.93)).frame(height: menuBarHeight)
        }
        .ignoresSafeArea()
    }
}
