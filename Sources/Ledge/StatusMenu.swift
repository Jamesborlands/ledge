import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Ledge")
        image?.isTemplate = true
        item.button?.image = image
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        let app = AppDelegate.shared!

        menu.addItem(ClosureMenuItem("New Shelf", symbol: "tray.and.arrow.down", key: "d", modifiers: [.option, .shift]) { app.newShelf() })
        menu.addItem(ClosureMenuItem("New Shelf from Clipboard", symbol: "doc.on.clipboard", key: "v", modifiers: [.option, .shift]) { app.newShelfFromClipboard() })
        menu.addItem(.separator())

        let history = ShelfStore.shared.history
        menu.addItem(NSMenuItem.sectionHeader(title: "Recent Shelves"))
        if history.isEmpty {
            let empty = NSMenuItem(title: "No shelves yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for shelf in history.prefix(5) { menu.addItem(shelfMenuItem(shelf)) }
        }

        let all = NSMenuItem(title: "All Shelves", action: nil, keyEquivalent: "")
        all.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil)
        let allMenu = NSMenu()
        for shelf in history { allMenu.addItem(shelfMenuItem(shelf)) }
        allMenu.addItem(.separator())
        allMenu.addItem(ClosureMenuItem("Clear History…", symbol: "trash") { [weak self] in self?.confirmClearHistory() })
        all.submenu = allMenu
        all.isEnabled = !history.isEmpty
        menu.addItem(all)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", symbol: "gearshape", key: ",") { app.showSettings() })
        menu.addItem(ClosureMenuItem("About Ledge", symbol: "info.circle") { app.showAbout() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit Ledge", symbol: "power", key: "q") { NSApp.terminate(nil) })
    }

    private func shelfMenuItem(_ shelf: Shelf) -> NSMenuItem {
        let id = shelf.id
        let item = ClosureMenuItem(shelf.menuTitle) { AppDelegate.shared.openShelf(id) }
        item.subtitle = dateFormatter.string(from: shelf.updatedAt)
        if let first = shelf.items.first, let icon = Thumbnails.shared.image(for: first.url).copy() as? NSImage {
            icon.size = NSSize(width: 28, height: 28)
            item.image = icon
        } else {
            item.image = NSImage(systemSymbolName: "tray", accessibilityDescription: nil)
        }
        return item
    }

    private func confirmClearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clear all recent shelves?"
        alert.informativeText = "Shelves that are open stay. Your original files aren't touched, but text, images and zips saved by Ledge are deleted."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            ShelfStore.shared.clearHistory(keeping: AppDelegate.shared.openShelfIDs)
        }
    }
}
