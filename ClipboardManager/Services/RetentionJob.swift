// ClipboardManager/Services/RetentionJob.swift
import Foundation

@MainActor
final class RetentionJob {

    private let store: ClipboardStore
    private let settings: () -> Settings

    private var timer: Timer?

    /// `settings` is a closure so tests can inject a custom UserDefaults.
    init(store: ClipboardStore, settings: @escaping () -> Settings = { Settings() }) {
        self.store = store
        self.settings = settings
    }

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

    /// One pass: age purge first, then count cap. Reads current limits from
    /// settings each time so changes apply on the next hourly tick.
    func runOnce() throws {
        let s = settings()
        // Int.max sentinel means "Forever" / "Unlimited" — skip that purge.
        if s.retentionDays != .max {
            try store.purgeOlderThan(days: s.retentionDays)
        }
        if s.historyLimit != .max {
            try store.purgeBeyondCount(max: s.historyLimit)
        }
    }
}
