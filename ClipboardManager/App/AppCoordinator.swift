// ClipboardManager/App/AppCoordinator.swift
import AppKit

@MainActor
final class AppCoordinator {
    private let store: ClipboardStore
    private let blobStore: BlobStore
    private let viewModel: ClipboardViewModel
    private let menuBar: MenuBarController
    private let drawer: DrawerWindowController
    private let hotkey: HotkeyService
    private let monitor: PasteboardMonitor
    private let retention: RetentionJob

    init() throws {
        let store = try ClipboardStore()
        try store.seedDefaultExclusionsIfNeeded()
        self.store = store

        let blobStore = try BlobStore()
        self.blobStore = blobStore

        let viewModel = ClipboardViewModel(store: store)
        self.viewModel = viewModel

        let drawer = DrawerWindowController(viewModel: viewModel, blobStore: blobStore)
        self.drawer = drawer

        self.menuBar = MenuBarController { drawer.toggle() }
        self.hotkey = HotkeyService { drawer.toggle() }
        self.monitor = PasteboardMonitor(store: store, blobStore: blobStore)
        self.retention = RetentionJob(store: store)
    }

    func start() {
        Log.coordinator.info("coordinator starting")
        hotkey.start()
        monitor.start()
        retention.start()
    }
}
