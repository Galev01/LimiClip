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
    private var screenFreezeWindow: NSWindow?
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
            onCompactToggle: { compact.toggle(near: NSEvent.mouseLocation) }
        )
        self.retention = RetentionJob(store: store, blobStore: blobStore)
        self.screenshotImporter = ScreenshotImporter(store: store, blobStore: blobStore)

        drawer.onAnnotate = { [weak self] item in self?.presentAnnotation(for: item) }
        hotkey.onScreenshot = { [weak self] in self?.presentScreenFreeze() }
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
        presentAnnotation(base: nsImage)
    }

    /// The three flattened-PNG output actions shared by the annotation editor
    /// (drawer images) and the screen-freeze overlay (fresh captures).
    private func annotationOutputs() -> (copy: (Data) -> Void,
                                         folder: (Data) -> Void,
                                         history: (Data) -> Void) {
        let copy: (Data) -> Void = { png in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
        }
        let folder: (Data) -> Void = { [settings] png in
            let folder = AnnotationFolder.resolve(bookmark: settings.annotationSaveBookmark)
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            do { _ = try AnnotationFolder.write(png: png, to: folder,
                                                timestamp: Int64(Date().timeIntervalSince1970)) }
            catch { Log.coordinator.error("annotate save failed: \(error.localizedDescription, privacy: .public)") }
        }
        let history: (Data) -> Void = { [store, blobStore] png in
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
        }
        return (copy, folder, history)
    }

    /// Opens the annotation editor on an in-memory image (e.g. a stored drawer
    /// image being re-annotated). The user decides its fate via the editor's
    /// Copy / Save-to-Folder / Save-to-History actions.
    func presentAnnotation(base nsImage: NSImage) {
        let outputs = annotationOutputs()
        let view = ImageAnnotationView(
            base: nsImage,
            onCopy: outputs.copy,
            onSaveToFolder: outputs.folder,
            onSaveToHistory: outputs.history,
            onClose: { [weak self] in self?.annotationWindow?.close(); self?.annotationWindow = nil }
        )
        let panel = AnnotationPanel(content: view, size: Self.annotationPanelSize(for: nsImage))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        annotationWindow = panel
    }

    /// iShot-style capture: silently grab the screen, freeze it under a
    /// full-screen overlay, let the user select a region and draw on it, then
    /// copy / save / store the annotated crop.
    func presentScreenFreeze() {
        guard screenFreezeWindow == nil, let screen = NSScreen.main else { return }
        // Phase 1: live region selection (screen is NOT frozen yet) — pure AppKit.
        let selectionView = SelectionOverlayNSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        selectionView.onSelected = { [weak self] rect in self?.captureAndAnnotate(selection: rect, screen: screen) }
        selectionView.onCancel = { [weak self] in self?.dismissScreenFreeze() }
        let window = makeFreezeWindow(screen: screen)
        window.contentView = selectionView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(selectionView)
        NSApp.activate(ignoringOtherApps: true)
        screenFreezeWindow = window
    }

    /// Phase 2: hide the selection overlay (so it's not in the shot), capture
    /// the now-live screen, then present the in-place annotation overlay on the
    /// frozen capture for the chosen region.
    private func captureAndAnnotate(selection: CGRect, screen: NSScreen) {
        screenFreezeWindow?.orderOut(nil)
        screenFreezeWindow = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Let the overlay fully leave the screen before the grab.
            try? await Task.sleep(nanoseconds: 60_000_000)
            let data = await ScreenCapturer.captureMainDisplayPNG()
            guard let data, let image = NSImage(data: data) else {
                Log.coordinator.error("screen freeze: capture failed (Screen Recording permission?)")
                return
            }
            let outputs = self.annotationOutputs()
            let view = ScreenFreezeView(
                full: image,
                viewSize: screen.frame.size,
                scale: screen.backingScaleFactor,
                selRect: selection,
                onCopy: outputs.copy,
                onSaveToFolder: outputs.folder,
                onSaveToHistory: outputs.history,
                onClose: { [weak self] in self?.dismissScreenFreeze() }
            )
            let window = self.makeFreezeWindow(screen: screen)
            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.screenFreezeWindow = window
        }
    }

    private func dismissScreenFreeze() {
        screenFreezeWindow?.orderOut(nil)
        screenFreezeWindow = nil
    }

    /// Builds a borderless, transparent, top-level overlay window covering
    /// `screen`. The caller sets `contentView`.
    private func makeFreezeWindow(screen: NSScreen) -> NSWindow {
        let window = ScreenFreezeWindow(contentRect: screen.frame,
                                        styleMask: [.borderless],
                                        backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.setFrame(screen.frame, display: true)
        return window
    }

    /// Panel size that fits the image (aspect-preserving) within sane bounds,
    /// plus room for the toolbar/divider and the canvas padding.
    static func annotationPanelSize(for image: NSImage) -> NSSize {
        let maxImageW: CGFloat = 680, maxImageH: CGFloat = 440
        let aspect = image.size.width > 0 && image.size.height > 0
            ? image.size.width / image.size.height : 1.4
        var w = maxImageW
        var h = w / aspect
        if h > maxImageH { h = maxImageH; w = h * aspect }
        let toolbarAndChrome: CGFloat = 60   // toolbar + divider + paddings
        return NSSize(width: max(w, 360) + 16, height: max(h, 240) + toolbarAndChrome)
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

    /// Reads a bitmap image off the general pasteboard (PNG/TIFF), or nil if no
    /// image is present. Retained as a small utility.
    static func imageFromPasteboard() -> NSImage? {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
           let image = NSImage(data: data) {
            return image
        }
        return NSImage(pasteboard: pb)
    }
}
