// ClipboardManager/ClipboardViewModel.swift
import Foundation

enum DrawerTab: String, CaseIterable, Identifiable, Sendable {
    case all, text, images, files, pinned
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .images: return "Images"
        case .files: return "Files"
        case .pinned: return "Pinned"
        }
    }
}

@MainActor
final class ClipboardViewModel: ObservableObject {

    @Published private(set) var items: [Item] = []
    @Published var selectedTab: DrawerTab = .all {
        didSet { focusedIndex = 0; refilter() }
    }
    @Published var searchQuery: String = "" {
        didSet { focusedIndex = 0; refilter() }
    }
    /// Whether the drawer's search field is expanded. Lives here (not view
    /// @State) so the window controller can reset it when the drawer reopens.
    @Published var searchExpanded: Bool = false
    @Published private(set) var focusedIndex: Int = 0
    @Published private(set) var filteredItems: [Item] = []

    private let store: ClipboardStore
    private let visibleLimit: Int
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
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func reload() {
        do {
            items = try store.recentItems(limit: visibleLimit)
        } catch {
            Log.app.error("view model reload failed: \(error.localizedDescription, privacy: .public)")
            items = []
        }
        refilter()
        focusedIndex = min(focusedIndex, max(0, filteredItems.count - 1))
    }

    private func refilter() {
        var list = items
        switch selectedTab {
        case .all:    break
        case .text:   list = list.filter { $0.kind == "text" }
        case .images: list = list.filter { $0.kind == "image" }
        case .files:  list = list.filter { $0.kind == "file" }
        case .pinned: list = list.filter { $0.pinned }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { item in
                let bag = [item.body, item.sourceApp ?? ""].joined(separator: " ").lowercased()
                return bag.contains(q)
            }
        }
        filteredItems = list
    }

    var currentItem: Item? {
        let list = filteredItems
        guard !list.isEmpty, focusedIndex < list.count, focusedIndex >= 0 else { return nil }
        return list[focusedIndex]
    }

    func moveFocus(by delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { focusedIndex = 0; return }
        focusedIndex = max(0, min(count - 1, focusedIndex + delta))
    }

    func jumpTo(index: Int) {
        let count = filteredItems.count
        guard count > 0 else { focusedIndex = 0; return }
        focusedIndex = max(0, min(count - 1, index))
    }

    /// Clears search text/expansion and focus. Called when the drawer is
    /// (re)shown so each open starts from a clean slate — a stale query
    /// otherwise hides items and a focused field swallows arrow keys.
    func resetTransientUIState() {
        searchExpanded = false
        searchQuery = ""   // didSet resets focusedIndex and refilters
    }
}
