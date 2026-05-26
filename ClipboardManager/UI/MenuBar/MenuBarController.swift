// ClipboardManager/UI/MenuBar/MenuBarController.swift
import AppKit

@MainActor
final class MenuBarController: NSObject {

    private let statusItem: NSStatusItem
    private let onOpenClipboard: @MainActor () -> Void
    private let onOpenPreferences: @MainActor () -> Void

    init(
        onOpenClipboard: @escaping @MainActor () -> Void,
        onOpenPreferences: @escaping @MainActor () -> Void
    ) {
        self.onOpenClipboard = onOpenClipboard
        self.onOpenPreferences = onOpenPreferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configure()
    }

    private func configure() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "doc.on.clipboard",
                            accessibilityDescription: "Clipboard Manager")
        image?.isTemplate = true
        button.image = image
        // Setting `statusItem.menu` makes NSStatusItem show the menu on click
        // (and removes our previous custom action binding).
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "Open Clipboard",
            action: #selector(openClipboardClicked),
            keyEquivalent: "v"
        )
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        menu.addItem(openItem)

        let prefsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferencesClicked),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Clipboard Manager",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openClipboardClicked() {
        Log.menuBar.info("menu: open clipboard")
        onOpenClipboard()
    }

    @objc private func openPreferencesClicked() {
        Log.menuBar.info("menu: preferences")
        onOpenPreferences()
    }

    @objc private func quitClicked() {
        Log.menuBar.info("menu: quit")
        NSApp.terminate(nil)
    }
}
