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

    /// `Ledge --shelf <file>... [--snapshot out.png]` opens a shelf holding those files (used for testing);
    /// `--settings-snapshot out.png` renders the Settings window. Launch these with `open` (see scripts/snapshots.sh).
    private func handleTestArguments() {
        let args = CommandLine.arguments
        if args.contains("--clipboard") { newShelfFromClipboard() }
        if let i = args.firstIndex(of: "--settings-snapshot"), i + 1 < args.count {
            showSettings()
            Self.snapshot(after: 1.5, settingsWindow?.contentView, to: URL(fileURLWithPath: args[i + 1])) {}
        }
        if let i = args.firstIndex(of: "--glow-snapshot"), i + 1 < args.count, let screen = ShakeDetector.notchScreen {
            let glow = NotchGlow()
            glow.update(proximity: 1, zone: ShakeDetector.notchZone(on: screen))
            if args.contains("--flare") { glow.flare() }
            Self.snapshot(after: 1.2, glow.contentView, to: URL(fileURLWithPath: args[i + 1])) { _ = glow }
        }
        if args.contains("--print-notch") {
            let screen = NSScreen.screens[0]
            print("notch zone:", ShakeDetector.notchZone(at: NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 1)) ?? .zero,
                  "screen:", screen.frame, "left:", screen.auxiliaryTopLeftArea ?? .zero, "right:", screen.auxiliaryTopRightArea ?? .zero)
            fflush(stdout)
        }
        guard let index = args.firstIndex(of: "--shelf") else { return }
        let paths = args[(index + 1)...].prefix { !$0.hasPrefix("--") }
        let controller = newShelf()
        ShelfStore.shared.add(paths.map { ShelfItem(url: URL(fileURLWithPath: $0), owned: false) }, to: controller.shelfID)
        if args.contains("--drop-target") { controller.isDropTarget = true }
        if let snap = args.firstIndex(of: "--snapshot"), snap + 1 < args.count {
            let out = URL(fileURLWithPath: args[snap + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let view = controller.panel.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                print("shelf frame:", controller.panel.frame)
                fflush(stdout)
                try? rep.representation(using: .png, properties: [:])?.write(to: out)
            }
        }
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
