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

    private let store: ClipboardStore
    private let blobStore: BlobStore
    private let settings: () -> Settings

    init(store: ClipboardStore, blobStore: BlobStore, settings: @escaping () -> Settings = { Settings() }) {
        self.store = store
        self.blobStore = blobStore
        self.settings = settings
    }

    /// Reads a screenshot file, downsamples + re-encodes it via `ImageProcessor`,
    /// writes the (encrypted) thumbnail blob, and records an image row. Dedup,
    /// encryption, and the image cap are handled by `ClipboardStore.recordImage`.
    /// Returns nil if the file can't be read or isn't a decodable image (logged,
    /// never throws on a bad/locked file).
    @discardableResult
    func importFile(at url: URL) throws -> Item? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Log.app.error("screenshot import: cannot read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let processed: ImageProcessor.Result
        do {
            processed = try ImageProcessor.process(data: data)
        } catch {
            Log.app.error("screenshot import: not a decodable image: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        let blobPath = try blobStore.write(data: processed.thumbnailData, fileExtension: "png")
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try store.recordImage(
            contentHash: hash,
            blobPath: blobPath,
            dimensions: processed.pixelSize,
            byteSize: data.count,
            sourceApp: "Screenshot",
            sourceBundleId: nil
        )
    }

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
