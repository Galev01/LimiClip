// ClipboardManager/UI/MenuBar/MenuBarController.swift
import AppKit

@MainActor
final class MenuBarController: NSObject {

    private let statusItem: NSStatusItem
    private let onOpenClipboard: @MainActor () -> Void
    private let onOpenPreferences: @MainActor () -> Void
    private let onPause: @MainActor (PauseChoice) -> Void
    private let onResume: @MainActor () -> Void
    private let isPaused: @MainActor () -> Bool

    private var pauseItems: [NSMenuItem] = []
    private var resumeItem: NSMenuItem?

    init(
        onOpenClipboard: @escaping @MainActor () -> Void,
        onOpenPreferences: @escaping @MainActor () -> Void,
        onPause: @escaping @MainActor (PauseChoice) -> Void = { _ in },
        onResume: @escaping @MainActor () -> Void = {},
        isPaused: @escaping @MainActor () -> Bool = { false }
    ) {
        self.onOpenClipboard = onOpenClipboard
        self.onOpenPreferences = onOpenPreferences
        self.onPause = onPause
        self.onResume = onResume
        self.isPaused = isPaused
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configure()
    }

    private func configure() {
        guard let button = statusItem.button else { return }
        button.image = makeImage(symbol: PauseState.statusSymbolName(isPaused: isPaused()))
        // Setting `statusItem.menu` makes NSStatusItem show the menu on click.
        statusItem.menu = makeMenu()
    }

    private func makeImage(symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "LimiClip")
        image?.isTemplate = true
        return image
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false   // we manage enabled state ourselves
        menu.delegate = self

        let openItem = NSMenuItem(title: "Open Clipboard", action: #selector(openClipboardClicked), keyEquivalent: "v")
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        menu.addItem(openItem)

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferencesClicked), keyEquivalent: ",")
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        // Pause / Resume.
        let pause15 = NSMenuItem(title: PauseChoice.fifteenMinutes.menuTitle, action: #selector(pause15Clicked), keyEquivalent: "")
        let pause1h = NSMenuItem(title: PauseChoice.oneHour.menuTitle, action: #selector(pause1hClicked), keyEquivalent: "")
        let pauseUntil = NSMenuItem(title: PauseChoice.untilResumed.menuTitle, action: #selector(pauseUntilClicked), keyEquivalent: "")
        let resume = NSMenuItem(title: "Resume Clipboard", action: #selector(resumeClicked), keyEquivalent: "")
        for item in [pause15, pause1h, pauseUntil, resume] {
            item.target = self
            menu.addItem(item)
        }
        pauseItems = [pause15, pause1h, pauseUntil]
        resumeItem = resume

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LimiClip", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        refreshStatus()
        return menu
    }

    /// Updates the status-bar icon and the enabled state of the pause/resume
    /// items to reflect whether capture is currently paused.
    private func refreshStatus() {
        let paused = isPaused()
        statusItem.button?.image = makeImage(symbol: PauseState.statusSymbolName(isPaused: paused))
        resumeItem?.isEnabled = paused
        pauseItems.forEach { $0.isEnabled = !paused }
    }

    @objc private func openClipboardClicked() {
        Log.menuBar.info("menu: open clipboard")
        onOpenClipboard()
    }

    @objc private func openPreferencesClicked() {
        Log.menuBar.info("menu: preferences")
        onOpenPreferences()
    }

    @objc private func pause15Clicked() { onPause(.fifteenMinutes); refreshStatus() }
    @objc private func pause1hClicked() { onPause(.oneHour); refreshStatus() }
    @objc private func pauseUntilClicked() { onPause(.untilResumed); refreshStatus() }
    @objc private func resumeClicked() { onResume(); refreshStatus() }

    @objc private func quitClicked() {
        Log.menuBar.info("menu: quit")
        NSApp.terminate(nil)
    }

    // MARK: - Test hooks

    func pause15ForTesting() { pause15Clicked() }
    func resumeForTesting() { resumeClicked() }
    var statusSymbolNameForTesting: String { PauseState.statusSymbolName(isPaused: isPaused()) }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // A pause may have expired since the menu was built; refresh on open.
        refreshStatus()
    }
}
