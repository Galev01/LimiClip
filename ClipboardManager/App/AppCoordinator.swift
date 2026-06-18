// ClipboardManager/App/AppCoordinator.swift
import AppKit
import SwiftUI
import CryptoKit

@MainActor
final class AppCoordinator {
    private let store: ClipboardStore
    private let blobStore: BlobStore
    private let settings = Settings()
    private var annotationWindow: NSWindow?
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
    private let screenshotImporter: ScreenshotImporter

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
        self.screenshotImporter = ScreenshotImporter(store: store, blobStore: blobStore)

        drawer.onAnnotate = { [weak self] item in self?.presentAnnotation(for: item) }
    }

    /// One-time alert explaining that the encryption key changed so older
    /// encrypted images could not be recovered and were removed.
    private func surfaceKeyMismatch(prunedCount: Int) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Encryption key changed"
        alert.informativeText = prunedCount > 0
            ? "The app's encryption key changed (this usually happens after reinstalling or re-signing the app). \(prunedCount) older image\(prunedCount == 1 ? "" : "s") could no longer be decrypted and \(prunedCount == 1 ? "was" : "were") removed. New clipboard items are unaffected."
            : "The app's encryption key changed (this usually happens after reinstalling or re-signing the app). Previously stored encrypted items may no longer be readable. New clipboard items are unaffected."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func presentAnnotation(for item: Item) {
        guard let path = item.blobPath,
              let nsImage = ImageCache.shared.image(forKey: path, blobStore: blobStore, path: path)
        else { Log.coordinator.error("annotate: cannot load image blob"); return }

        let view = ImageAnnotationView(
            base: nsImage,
            onCopy: { png in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(png, forType: .png)
            },
            onSaveToFolder: { [settings] png in
                let folder = AnnotationFolder.resolve(bookmark: settings.annotationSaveBookmark)
                let scoped = folder.startAccessingSecurityScopedResource()
                defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
                do { _ = try AnnotationFolder.write(png: png, to: folder,
                                                    timestamp: Int64(Date().timeIntervalSince1970)) }
                catch { Log.coordinator.error("annotate save failed: \(error.localizedDescription, privacy: .public)") }
            },
            onSaveToHistory: { [store, blobStore] png in
                do {
                    let processed = try ImageProcessor.process(data: png)
                    let blobPath = try blobStore.write(data: processed.thumbnailData, fileExtension: "png")
                    let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                    let recorded = try store.recordImage(contentHash: hash, blobPath: blobPath,
                        dimensions: processed.pixelSize, byteSize: png.count,
                        sourceApp: "Annotation", sourceBundleId: nil)
                    if recorded == nil || (recorded!.blobPath != nil && recorded!.blobPath != blobPath) {
                        try? blobStore.delete(relativePath: blobPath)
                    }
                } catch { Log.coordinator.error("annotate history save failed: \(error.localizedDescription, privacy: .public)") }
            },
            onClose: { [weak self] in self?.annotationWindow?.close(); self?.annotationWindow = nil }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Annotate Image"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 560))
        window.center()
        let wc = NSWindowController(window: window)
        wc.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        annotationWindow = window
    }

    func start() {
        applyAppearance()
        Log.coordinator.info("coordinator starting")

        // If the encryption key changed since data was written (the re-signed /
        // stale-binary trap), previously-stored image blobs can no longer be
        // decrypted and would render as blank cards forever. Prune them, and
        // tell the user once why their old images disappeared.
        do {
            let pruned = try store.pruneUndecryptableImages(blobStore: blobStore)
            if pruned > 0 {
                Log.coordinator.error("pruned \(pruned, privacy: .public) undecryptable image item(s)")
            }
            if DatabaseKey.didDetectKeyMismatch {
                surfaceKeyMismatch(prunedCount: pruned)
            }
        } catch {
            Log.coordinator.error("prune undecryptable images failed: \(error.localizedDescription, privacy: .public)")
        }

        hotkey.start()
        monitor.start()
        screenshotImporter.start()
        retention.start()

        // Re-apply appearance if the user changes it in Preferences.
        appearanceObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.applyAppearance()
                self?.applyScreenshotCaptureSetting()
            }
        }
    }

    deinit {
        if let token = appearanceObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func applyScreenshotCaptureSetting() {
        if Settings().captureScreenshotFiles {
            screenshotImporter.start()   // no-op if already running
        } else {
            screenshotImporter.stop()
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
