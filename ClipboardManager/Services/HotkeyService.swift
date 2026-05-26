// ClipboardManager/Services/HotkeyService.swift
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that toggles the bottom drawer. Default: ⌘⇧V.
    static let toggleDrawer = Self("toggleDrawer", default: .init(.v, modifiers: [.command, .shift]))

    /// Global shortcut that triggers an interactive screenshot to the
    /// clipboard. The system `screencapture -i -c` tool runs; the resulting
    /// image lands on NSPasteboard.general and is picked up by the monitor
    /// like any other clipboard change. Default: ⌘⇧A.
    static let screenshotToClipboard = Self("screenshotToClipboard", default: .init(.a, modifiers: [.command, .shift]))

    /// Global shortcut that opens the compact cursor-adjacent popup.
    /// Ships with no default — user assigns in Preferences → Shortcuts.
    static let toggleCompactPopup = Self("toggleCompactPopup")
}

@MainActor
final class HotkeyService {
    private let onToggle: @MainActor () -> Void
    private let onScreenshot: @MainActor () -> Void
    private let onCompactToggle: @MainActor () -> Void

    init(
        onToggle: @escaping @MainActor () -> Void,
        onScreenshot: @escaping @MainActor () -> Void,
        onCompactToggle: @escaping @MainActor () -> Void = { @MainActor in }
    ) {
        self.onToggle = onToggle
        self.onScreenshot = onScreenshot
        self.onCompactToggle = onCompactToggle
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleDrawer) { [weak self] in
            Log.hotkey.info("toggleDrawer fired")
            self?.onToggle()
        }
        KeyboardShortcuts.onKeyDown(for: .screenshotToClipboard) { [weak self] in
            Log.hotkey.info("screenshotToClipboard fired")
            self?.onScreenshot()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleCompactPopup) { [weak self] in
            Log.hotkey.info("toggleCompactPopup fired")
            self?.onCompactToggle()
        }
    }

    func stop() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
