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

    private var query: NSMetadataQuery?
    private var seenPaths: Set<String> = []
    private var hasGathered = false

    func start() {
        guard query == nil else { return }
        guard settings().captureScreenshotFiles else {
            Log.app.info("screenshot import disabled by setting")
            return
        }
        let folder = Self.resolveScreenshotFolder(
            location: CFPreferencesCopyAppValue("location" as CFString,
                                                "com.apple.screencapture" as CFString) as? String
        )
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        q.searchScopes = [folder]
        q.operationQueue = .main

        NotificationCenter.default.addObserver(
            self, selector: #selector(gatheringFinished(_:)),
            name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryUpdated(_:)),
            name: .NSMetadataQueryDidUpdate, object: q)

        q.start()
        query = q
        Log.app.info("screenshot import watching \(folder.path, privacy: .public)")
    }

    func stop() {
        guard let q = query else { return }
        q.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: q)
        query = nil
        hasGathered = false
        seenPaths.removeAll()
    }

    /// Initial gather = screenshots that already exist at launch. Record them
    /// as "seen" so we never back-fill the user's old Desktop screenshots.
    ///
    /// Soundness: operationQueue=.main guarantees delivery on the main thread.
    /// The Thread.isMainThread guard below is a defensive fallback in case that
    /// ever changes (e.g. if the query is reconfigured).
    @objc nonisolated private func gatheringFinished(_ note: Notification) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { self.handleGatheringFinished() }
        } else {
            Task { @MainActor in self.handleGatheringFinished() }
        }
    }

    @MainActor private func handleGatheringFinished() {
        guard let q = query else { return }
        q.disableUpdates()
        for i in 0..<q.resultCount {
            if let item = q.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                seenPaths.insert(path)
            }
        }
        hasGathered = true
        q.enableUpdates()
    }

    /// A new (or changed) screenshot appeared. Import any path not seen yet.
    ///
    /// Soundness: operationQueue=.main guarantees delivery on the main thread.
    /// The Thread.isMainThread guard below is a defensive fallback in case that
    /// ever changes (e.g. if the query is reconfigured).
    @objc nonisolated private func queryUpdated(_ note: Notification) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { self.handleUpdate() }
        } else {
            Task { @MainActor in self.handleUpdate() }
        }
    }

    @MainActor private func handleUpdate() {
        guard hasGathered, let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !seenPaths.contains(path) else { continue }
            // Insert into seenPaths only after a successful import so that a
            // transient partial-write read (importFile returns nil) is retried
            // on the next NSMetadataQueryDidUpdate notification.
            do {
                if let _ = try importFile(at: URL(fileURLWithPath: path)) {
                    seenPaths.insert(path)
                }
                // nil return means unreadable/non-image; leave path unseen for retry
            } catch {
                Log.app.error("screenshot import failed: \(error.localizedDescription, privacy: .public)")
                // Do not mark seen on error — allow retry on next update
            }
        }
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
