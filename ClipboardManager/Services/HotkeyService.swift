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

    /// Global shortcut that copies the current selection and APPENDS it to the
    /// clipboard text (space-separated) instead of replacing it. Ships with no
    /// default — user assigns in Preferences → Shortcuts.
    static let chainCopyAppend = Self("chainCopyAppend")

    /// Global shortcut that starts a screen recording (or stops the one in
    /// progress — the coordinator treats it as a toggle). Ships with no default
    /// — user assigns in Preferences → Shortcuts.
    static let startRecording = Self("startRecording")
}

@MainActor
final class HotkeyService {
    private let onToggle: @MainActor () -> Void
    /// Assignable after construction so the coordinator can wire it once `self`
    /// is fully initialized (the handler fires later, in `start()`).
    var onScreenshot: @MainActor () -> Void
    /// Assignable after construction (see `onScreenshot`).
    var onChainCopy: @MainActor () -> Void = { }
    /// Assignable after construction (see `onScreenshot`). Fires for the
    /// start/stop-recording shortcut; the coordinator toggles recording.
    var onStartRecording: @MainActor () -> Void = { }
    private let onCompactToggle: @MainActor () -> Void

    init(
        onToggle: @escaping @MainActor () -> Void,
        onScreenshot: @escaping @MainActor () -> Void = { @MainActor in },
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
        KeyboardShortcuts.onKeyDown(for: .chainCopyAppend) { [weak self] in
            Log.hotkey.info("chainCopyAppend fired")
            self?.onChainCopy()
        }
        KeyboardShortcuts.onKeyDown(for: .startRecording) { [weak self] in
            Log.hotkey.info("startRecording fired")
            self?.onStartRecording()
        }
    }

    func stop() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
