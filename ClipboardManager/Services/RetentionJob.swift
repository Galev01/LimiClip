// ClipboardManager/Services/RetentionJob.swift
import Foundation

@MainActor
final class RetentionJob {

    private let store: ClipboardStore
    private let retentionDays: Int
    private let maxItems: Int

    private var timer: Timer?

    init(store: ClipboardStore, retentionDays: Int = 90, maxItems: Int = 5_000) {
        self.store = store
        self.retentionDays = retentionDays
        self.maxItems = maxItems
    }

    /// Starts a once-per-hour cleanup timer and runs an immediate pass.
    func start() {
        do { try runOnce() } catch { Log.app.error("retention initial pass: \(error.localizedDescription, privacy: .public)") }

        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                do { try self?.runOnce() } catch {
                    Log.app.error("retention pass: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One pass: age purge first, then count cap.
    func runOnce() throws {
        try store.purgeOlderThan(days: retentionDays)
        try store.purgeBeyondCount(max: maxItems)
    }
}
