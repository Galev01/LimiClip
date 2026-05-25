// ClipboardManager/Services/PasteboardMonitor.swift
import AppKit
import Foundation
import CryptoKit

/// Polls `NSPasteboard.changeCount` every 250 ms and records changes into
/// the `ClipboardStore`. The kind router runs after the privacy + exclusion
/// filters, with precedence: file URL → image → text.
@MainActor
final class PasteboardMonitor {

    static let pollInterval: TimeInterval = 0.25

    typealias FrontmostAppProvider = () -> (name: String?, bundleId: String?)

    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let blobStore: BlobStore
    private let frontmostApp: FrontmostAppProvider

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var pausedUntil: Date = .distantPast

    private static let concealedTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("Pasteboard generator type"),
    ]

    init(
        pasteboard: NSPasteboard = .general,
        store: ClipboardStore,
        blobStore: BlobStore? = nil,
        frontmostApp: @escaping FrontmostAppProvider = PasteboardMonitor.defaultFrontmostApp
    ) {
        self.pasteboard = pasteboard
        self.store = store
        if let blobStore {
            self.blobStore = blobStore
        } else {
            // Fall back to a temp directory if no blob store is injected.
            // Production code MUST inject the shared production BlobStore.
            self.blobStore = (try? BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("clipboard-monitor-\(UUID().uuidString)", isDirectory: true)))
                ?? (try! BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))
        }
        self.frontmostApp = frontmostApp
    }

    nonisolated static func defaultFrontmostApp() -> (name: String?, bundleId: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.app.info("pasteboard monitor started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pause(until date: Date) {
        pausedUntil = date
    }

    func tickForTesting() { tick() }

    private func tick() {
        let current = pasteboard.changeCount
        defer { lastChangeCount = current }
        guard current != lastChangeCount else { return }
        guard Date() >= pausedUntil else {
            Log.app.debug("monitor paused, skipping change")
            return
        }
        route()
    }

    /// Decide what kind of item this pasteboard change represents and hand
    /// off to the appropriate capture method.
    private func route() {
        if let types = pasteboard.types, !Set(types).isDisjoint(with: Self.concealedTypes) {
            Log.app.info("skipping concealed pasteboard item")
            return
        }
        let (appName, bundleId) = frontmostApp()

        // 1. File URLs win.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let fileURLs = urls.filter { $0.isFileURL }
            if let first = fileURLs.first {
                captureFile(url: first, appName: appName, bundleId: bundleId)
                return
            }
        }

        // 2. Image types next.
        if let imageType = pickImageType(), let data = pasteboard.data(forType: imageType) {
            captureImage(data: data, appName: appName, bundleId: bundleId)
            return
        }

        // 3. Plain text.
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            do {
                _ = try store.recordText(text, sourceApp: appName, sourceBundleId: bundleId)
            } catch {
                Log.app.error("text record failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func pickImageType() -> NSPasteboard.PasteboardType? {
        let preferred: [NSPasteboard.PasteboardType] = [.png, .tiff]
        guard let available = pasteboard.types else { return nil }
        for t in preferred where available.contains(t) {
            return t
        }
        return nil
    }

    private func captureImage(data: Data, appName: String?, bundleId: String?) {
        do {
            let processed = try ImageProcessor.process(data: data)
            let blobPath = try blobStore.write(data: processed.thumbnailData, fileExtension: "png")
            let hash = Self.hashBytes(data)
            _ = try store.recordImage(
                contentHash: hash,
                blobPath: blobPath,
                dimensions: processed.pixelSize,
                byteSize: data.count,
                sourceApp: appName,
                sourceBundleId: bundleId
            )
        } catch {
            Log.app.error("image capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func captureFile(url: URL, appName: String?, bundleId: String?) {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let ref = FileReference(
                path: url.path,
                name: url.lastPathComponent,
                byteSize: size,
                modifiedAt: Int64(mtime)
            )
            _ = try store.recordFile(reference: ref, sourceApp: appName, sourceBundleId: bundleId)
        } catch {
            Log.app.error("file capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func hashBytes(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
