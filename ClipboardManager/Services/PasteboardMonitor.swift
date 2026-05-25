// ClipboardManager/Services/PasteboardMonitor.swift
import AppKit
import Foundation

/// Polls `NSPasteboard.changeCount` every 250 ms and records text changes
/// into the `ClipboardStore`. Filters: concealed pasteboard types, excluded
/// bundle IDs, paused-until timestamp, and (Phase 2 only) non-text content.
@MainActor
final class PasteboardMonitor {

    static let pollInterval: TimeInterval = 0.25

    /// Provider for the frontmost app's display name + bundle id at the moment
    /// of a pasteboard change. Injectable for tests.
    typealias FrontmostAppProvider = () -> (name: String?, bundleId: String?)

    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let frontmostApp: FrontmostAppProvider

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var pausedUntil: Date = .distantPast

    /// Pasteboard type identifiers that indicate concealed / password-manager
    /// data; we never record items where any of these is present.
    private static let concealedTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("Pasteboard generator type"),
    ]

    init(
        pasteboard: NSPasteboard = .general,
        store: ClipboardStore,
        frontmostApp: @escaping FrontmostAppProvider = PasteboardMonitor.defaultFrontmostApp
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.frontmostApp = frontmostApp
    }

    /// Default provider: reads `NSWorkspace.shared.frontmostApplication`.
    nonisolated static func defaultFrontmostApp() -> (name: String?, bundleId: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }

    /// Starts the polling timer on the main runloop. Idempotent.
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

    /// Synchronous tick — invoked by the timer in production, and directly by
    /// tests to advance the monitor deterministically.
    func tickForTesting() { tick() }

    private func tick() {
        let current = pasteboard.changeCount
        defer { lastChangeCount = current }
        guard current != lastChangeCount else { return }
        guard Date() >= pausedUntil else {
            Log.app.debug("monitor paused, skipping change")
            return
        }
        captureCurrentContents()
    }

    private func captureCurrentContents() {
        // 1. Privacy: concealed types win immediately.
        if let types = pasteboard.types, !Set(types).isDisjoint(with: Self.concealedTypes) {
            Log.app.info("skipping concealed pasteboard item")
            return
        }

        // 2. Phase 2 scope: TEXT only. Detect non-text types and skip with a log.
        if pasteboard.types?.contains(.string) != true {
            if let t = pasteboard.types {
                Log.app.debug("non-text pasteboard ignored in Phase 2 (types=\(t.map(\.rawValue), privacy: .public))")
            }
            return
        }

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return
        }

        // 3. Capture.
        let (appName, bundleId) = frontmostApp()
        do {
            _ = try store.recordText(text, sourceApp: appName, sourceBundleId: bundleId)
        } catch {
            Log.app.error("store insert failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
