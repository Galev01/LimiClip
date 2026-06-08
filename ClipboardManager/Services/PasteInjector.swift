// ClipboardManager/Services/PasteInjector.swift
import AppKit
import Foundation
import CoreGraphics

/// Writes a clipboard `Item` back to `NSPasteboard` and then synthesises
/// `⌘V` into the previously-active app.
///
/// The synthesis path requires Accessibility permission. We do not gate the
/// write on permission — even without Accessibility, the pasteboard
/// receives the content, so the user can paste manually.
@MainActor
final class PasteInjector {

    private let pasteboard: NSPasteboard
    private let blobStore: BlobStore

    init(pasteboard: NSPasteboard = .general, blobStore: BlobStore) {
        self.pasteboard = pasteboard
        self.blobStore = blobStore
    }

    // MARK: - Pasteboard writes

    /// Writes the item content to the pasteboard, kind-aware. If
    /// `asPlainText` is true, text items omit any rich-text representation.
    func writeToPasteboard(item: Item, asPlainText: Bool = false) throws {
        pasteboard.clearContents()
        switch item.kind {
        case "text":
            pasteboard.setString(item.body, forType: .string)
        case "image":
            guard let path = item.blobPath else { return }
            // If the blob can't be read (missing/corrupt file), degrade
            // gracefully: log and leave the pasteboard cleared rather than
            // throwing and breaking the paste flow (bug B3).
            guard let data = try? blobStore.read(relativePath: path) else {
                Log.app.error("paste: image blob unreadable at \(path, privacy: .public)")
                return
            }
            // Declare both PNG and TIFF explicitly. `writeObjects([NSImage])`
            // alone registers TIFF but NOT PNG, so PNG-only consumers (and
            // clipboard inspectors) see nothing. Declaring both covers every
            // consumer.
            if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                pasteboard.declareTypes([.png, .tiff], owner: nil)
                pasteboard.setData(data, forType: .png)
                pasteboard.setData(tiff, forType: .tiff)
            } else {
                pasteboard.declareTypes([.png], owner: nil)
                pasteboard.setData(data, forType: .png)
            }
        case "file":
            let ref = try FileReference.decodingJSON(item.body)
            let url = URL(fileURLWithPath: ref.path)
            pasteboard.writeObjects([url as NSURL])
        default:
            Log.app.error("unknown item kind for paste: \(item.kind, privacy: .public)")
        }
        _ = asPlainText   // currently a no-op; future Phase will branch RTF writes
    }

    // MARK: - Cmd-V synthesis

    /// Posts a `Cmd-V` keyDown + keyUp to the system event tap. If
    /// Accessibility permission is missing, macOS silently drops it.
    func synthesizePasteKeystroke() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        // Key code 9 == 'V'.
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
        Log.app.debug("synthesised ⌘V")
    }

    /// True if the host process has Accessibility permission granted.
    var hasAccessibilityPermission: Bool {
        return AXIsProcessTrusted()
    }

    /// Triggers the macOS system prompt asking the user to grant Accessibility
    /// permission, if not already granted. Returns the current trusted state.
    /// Use this lazily — only when the user actually tries to do something
    /// that requires the permission.
    @discardableResult
    func promptForAccessibilityIfNeeded() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: NSDictionary = [key: true]
        return AXIsProcessTrustedWithOptions(options)
    }
}
