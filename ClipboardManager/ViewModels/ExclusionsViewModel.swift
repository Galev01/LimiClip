// ClipboardManager/ViewModels/ExclusionsViewModel.swift
import Foundation
import Combine

@MainActor
final class ExclusionsViewModel: ObservableObject {

    @Published private(set) var exclusions: [Exclusion] = []

    private let store: ClipboardStore
    // `nonisolated(unsafe)` mirrors the pattern in ClipboardViewModel:
    // the token is written once during init (on the MainActor) and read
    // once during deinit; no concurrent access occurs.
    nonisolated(unsafe) private var notificationToken: (any NSObjectProtocol)?

    init(store: ClipboardStore) {
        self.store = store
        reload()
        notificationToken = NotificationCenter.default.addObserver(
            forName: .clipboardStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The observer is registered with queue: .main, so this closure
            // always runs on the main thread — use assumeIsolated to call the
            // @MainActor reload() synchronously without an async Task hop.
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    deinit {
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Public API

    func add(bundleId: String, name: String) {
        do {
            try store.addExclusion(bundleId: bundleId, name: name)
            reload()
        } catch {
            Log.app.error("ExclusionsViewModel.add failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func remove(bundleId: String) {
        do {
            try store.removeExclusion(bundleId: bundleId)
            reload()
        } catch {
            Log.app.error("ExclusionsViewModel.remove failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func reload() {
        do {
            exclusions = try store.allExclusions()
        } catch {
            Log.app.error("ExclusionsViewModel.reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
