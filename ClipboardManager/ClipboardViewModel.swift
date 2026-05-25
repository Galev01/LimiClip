// ClipboardManager/ClipboardViewModel.swift
import Foundation
import Combine

@MainActor
final class ClipboardViewModel: ObservableObject {

    @Published private(set) var items: [Item] = []

    private let store: ClipboardStore
    private let visibleLimit: Int
    // nonisolated(unsafe) so deinit (which is nonisolated) can access the token
    // for synchronous, thread-safe removeObserver cleanup.
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init(store: ClipboardStore, visibleLimit: Int = 200) {
        self.store = store
        self.visibleLimit = visibleLimit
        observer = NotificationCenter.default.addObserver(
            forName: .clipboardStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func reload() {
        do {
            items = try store.recentItems(limit: visibleLimit)
        } catch {
            Log.app.error("view model reload failed: \(error.localizedDescription, privacy: .public)")
            items = []
        }
    }
}
