// ClipboardManager/UI/MenuBar/MenuBarController.swift
import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let onActivate: @MainActor () -> Void

    init(onActivate: @escaping @MainActor () -> Void) {
        self.onActivate = onActivate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configure()
    }

    private func configure() {
        guard let button = statusItem.button else { return }
        // Use a template SF Symbol; replaced by a custom asset later.
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")
        image?.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp])
    }

    @objc private func handleClick() {
        Log.menuBar.info("menu bar status item clicked")
        onActivate()
    }
}
