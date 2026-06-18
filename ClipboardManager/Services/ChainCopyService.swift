// ClipboardManager/Services/ChainCopyService.swift
import AppKit
import CoreGraphics

/// "Chain copy": appends the current selection to whatever text is already on
/// the clipboard, separated by a space. Pressing the configurable hotkey on a
/// new selection grows the clipboard text:
///
///     ⌘C "hi"            → clipboard: "hi"
///     chain-copy "mister"  → clipboard: "hi mister"
///     chain-copy "there"   → clipboard: "hi mister there"
///
/// Synthesising ⌘C requires Accessibility permission (already used for paste).
@MainActor
final class ChainCopyService {

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Pure join used by `perform()`; separated out so it is unit-testable.
    nonisolated static func combine(previous: String, addition: String, separator: String = " ") -> String {
        if previous.isEmpty { return addition }
        if addition.isEmpty { return previous }
        return previous + separator + addition
    }

    /// Reads the current clipboard text, synthesises ⌘C to copy the active
    /// selection, then (once the pasteboard updates) replaces it with the
    /// combined text. No-op if nothing new gets copied (e.g. no selection, or
    /// Accessibility not granted) within the timeout.
    func perform() {
        let previous = pasteboard.string(forType: .string) ?? ""
        let beforeCount = pasteboard.changeCount
        synthesizeCopyKeystroke()
        pollForCopiedSelection(beforeCount: beforeCount, previous: previous, attempt: 0)
    }

    private func pollForCopiedSelection(beforeCount: Int, previous: String, attempt: Int) {
        if pasteboard.changeCount != beforeCount {
            let addition = pasteboard.string(forType: .string) ?? ""
            let combined = Self.combine(previous: previous, addition: addition)
            pasteboard.clearContents()
            pasteboard.setString(combined, forType: .string)
            Log.app.info("chain copy: appended selection (\(addition.count, privacy: .public) chars)")
            return
        }
        guard attempt < 10 else {   // ~0.5s budget
            Log.app.info("chain copy: no new selection copied; nothing appended")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pollForCopiedSelection(beforeCount: beforeCount, previous: previous, attempt: attempt + 1)
        }
    }

    /// Posts ⌘C (virtual key 8 == 'C'). macOS drops it silently without
    /// Accessibility permission.
    private func synthesizeCopyKeystroke() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}
