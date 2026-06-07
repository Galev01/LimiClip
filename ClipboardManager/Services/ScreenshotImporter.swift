// ClipboardManager/Services/ScreenshotImporter.swift
import AppKit
import Foundation
import CryptoKit

/// Imports macOS screenshots that are saved as *files* (the default ⌘⇧4
/// behaviour) into clipboard history. Such screenshots never touch the
/// pasteboard, so `PasteboardMonitor` cannot see them; this service watches
/// the screenshot folder instead and feeds new screenshots through the same
/// image pipeline (`ImageProcessor` → `BlobStore` → `ClipboardStore`).
@MainActor
final class ScreenshotImporter {

    /// Resolves the folder macOS writes screenshots to. `location` is the raw
    /// value of `com.apple.screencapture`'s `location` default (may be nil,
    /// a tilde path, or an absolute path). Falls back to ~/Desktop.
    static func resolveScreenshotFolder(location: String?) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let location, !location.isEmpty else {
            return home.appendingPathComponent("Desktop", isDirectory: true)
        }
        let expanded = (location as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}
