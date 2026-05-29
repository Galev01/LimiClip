// ClipboardManager/App/AppCoordinator.swift
import AppKit

@MainActor
final class AppCoordinator {
    private let store: ClipboardStore
    private let blobStore: BlobStore
    private let viewModel: ClipboardViewModel
    private let menuBar: MenuBarController
    private let drawer: DrawerWindowController
    private let compactPopup: CompactPopupWindowController
    private let hotkey: HotkeyService
    private let monitor: PasteboardMonitor
    private let retention: RetentionJob
    private let pasteInjector: PasteInjector
    private let exclusionsVM: ExclusionsViewModel
    private let preferencesWindow: PreferencesWindowController

    nonisolated(unsafe) private var appearanceObserver: NSObjectProtocol?
    private var lastAppearance: AppAppearance?

    init() throws {
        let blobStore = try BlobStore()
        self.blobStore = blobStore

        let store = try ClipboardStore(blobStore: blobStore)
        try store.seedDefaultExclusionsIfNeeded()
        self.store = store
        let exclusionsVM = ExclusionsViewModel(store: store)
        self.exclusionsVM = exclusionsVM
        self.preferencesWindow = PreferencesWindowController(exclusionsVM: exclusionsVM)

        let injector = PasteInjector(blobStore: blobStore)
        self.pasteInjector = injector

        let viewModel = ClipboardViewModel(store: store)
        self.viewModel = viewModel

        let drawer = DrawerWindowController(viewModel: viewModel, blobStore: blobStore, store: store, injector: injector)
        self.drawer = drawer

        let compact = CompactPopupWindowController(viewModel: viewModel, blobStore: blobStore, store: store, injector: injector)
        self.compactPopup = compact

        let monitor = PasteboardMonitor(store: store, blobStore: blobStore)
        self.monitor = monitor

        let prefs = self.preferencesWindow
        self.menuBar = MenuBarController(
            onOpenClipboard: { drawer.toggle() },
            onOpenPreferences: { prefs.show() },
            onPause: { choice in monitor.pause(until: choice.pausedUntil(from: Date())) },
            onResume: { monitor.pause(until: PauseState.resumeDate) },
            isPaused: { monitor.isPaused }
        )
        self.hotkey = HotkeyService(
            onToggle: { drawer.toggle() },
            onScreenshot: { AppCoordinator.captureScreenshotToClipboard(monitor: monitor) },
            onCompactToggle: { compact.toggle(near: NSEvent.mouseLocation) }
        )
        self.retention = RetentionJob(store: store, blobStore: blobStore)
    }

    func start() {
        applyAppearance()
        Log.coordinator.info("coordinator starting")
        hotkey.start()
        monitor.start()
        retention.start()

        // Re-apply appearance if the user changes it in Preferences.
        appearanceObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyAppearance() }
        }
    }

    deinit {
        if let token = appearanceObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func applyAppearance() {
        let appearance = Settings().appearance
        guard appearance != lastAppearance else { return }
        NSApp.appearance = appearance.nsAppearance
        lastAppearance = appearance
    }

    /// Spawns `screencapture -i -c` so the user can drag-select a region; the
    /// resulting image lands on NSPasteboard. When the "Save screenshots to
    /// history" setting is OFF (the default), capture is paused across the
    /// screencapture lifecycle so the image reaches the clipboard for pasting
    /// but is NOT recorded into history.
    static func captureScreenshotToClipboard(monitor: PasteboardMonitor, settings: Settings = Settings()) {
        let save = settings.saveScreenshots
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-c"]
        if !save {
            monitor.pause(until: .distantFuture)
            task.terminationHandler = { _ in
                // Keep paused briefly so the monitor's poll consumes (and
                // skips) the screenshot's changeCount, then resume.
                Task { @MainActor in
                    monitor.pause(until: Date().addingTimeInterval(PasteboardMonitor.pollInterval * 2))
                }
            }
        }
        do {
            try task.run()
            Log.coordinator.info("screencapture -i -c launched (save=\(save, privacy: .public))")
        } catch {
            if !save { monitor.pause(until: PauseState.resumeDate) }
            Log.coordinator.error("screencapture launch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
