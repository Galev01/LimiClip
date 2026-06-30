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

    // Screen recording (plan Task 6).
    private let recorder = ScreenRecorder()
    private let recordingChooser = RecordingChooserPanel()
    private let countdown = CountdownOverlay()
    private var recordingSelectionWindow: NSWindow?
    private var isRecording = false
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
    private let updater = UpdaterController()

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
        hotkey.onChainCopy = { [weak self] in self?.chainCopy.perform() }
        hotkey.onStartRecording = { [weak self] in self?.toggleRecording() }
        menuBar.onToggleRecording = { [weak self] in self?.toggleRecording() }
        menuBar.isRecording = { [weak self] in self?.isRecording ?? false }
        menuBar.onCheckForUpdates = { [weak self] in self?.updater.checkForUpdates() }
    }

    private let chainCopy = ChainCopyService()

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
        guard screenFreezeWindow == nil else { return }
        // Target the screen under the mouse (not necessarily the primary), so
        // selection and capture happen on the SAME display.
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
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
        let frame = screen.frame
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? frame.height
        let captureRect = ScreenCaptureGeometry.screencaptureRect(for: frame, primaryHeight: primaryHeight)
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Let the overlay fully leave the screen before the grab.
            try? await Task.sleep(nanoseconds: 60_000_000)
            let data = await ScreenCapturer.captureRegionPNG(globalRect: captureRect)
            guard let data, let image = NSImage(data: data),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                Log.coordinator.error("screen freeze: capture failed (Screen Recording permission?)")
                return
            }
            // Derive scale from the actual capture so cropping is exact regardless
            // of how screencapture rendered the display's resolution.
            let scale = frame.width > 0 ? CGFloat(cg.width) / frame.width : screen.backingScaleFactor
            let outputs = self.annotationOutputs()
            let view = ScreenFreezeView(
                full: image,
                viewSize: frame.size,
                scale: scale,
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

    // MARK: - Screen recording (plan Task 6)

    /// The Start-Recording hotkey and the menu-bar item both route here: start a
    /// new recording flow, or stop the one in progress. Never starts two at once.
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            beginRecordingFlow()
        }
    }

    /// Step 1: show the Region / Full Screen / Cancel chooser on the screen under
    /// the mouse. A choice advances to the region selection or straight to the
    /// countdown; Cancel (or Esc) aborts cleanly.
    private func beginRecordingFlow() {
        guard !isRecording else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }

        recordingChooser.show { [weak self] choice in
            guard let self else { return }
            switch choice {
            case .cancel:
                Log.coordinator.info("recording cancelled at chooser")
            case .fullScreen:
                self.startCountdownThenRecord(globalRect: Self.fullScreenGlobalRect(for: screen), screen: screen)
            case .region:
                self.presentRecordingSelection(on: screen)
            }
        }
    }

    /// Region path: reuse the crosshair selection overlay (the same NSView the
    /// screen-freeze flow uses). The selection is in top-left view points within
    /// the target screen; we map it to the global top-left rect `screencapture`
    /// expects, then proceed to the countdown.
    private func presentRecordingSelection(on screen: NSScreen) {
        let selectionView = SelectionOverlayNSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        selectionView.onSelected = { [weak self] rect in
            guard let self else { return }
            self.dismissRecordingSelection()
            let global = Self.regionGlobalRect(selection: rect, screen: screen)
            self.startCountdownThenRecord(globalRect: global, screen: screen)
        }
        selectionView.onCancel = { [weak self] in
            self?.dismissRecordingSelection()
            Log.coordinator.info("recording cancelled at selection")
        }
        let window = makeFreezeWindow(screen: screen)
        window.contentView = selectionView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(selectionView)
        NSApp.activate(ignoringOtherApps: true)
        recordingSelectionWindow = window
    }

    private func dismissRecordingSelection() {
        recordingSelectionWindow?.orderOut(nil)
        recordingSelectionWindow = nil
    }

    /// Step 3: the 3-2-1 countdown on the target screen, then launch the
    /// recording. Esc during the countdown aborts without recording.
    private func startCountdownThenRecord(globalRect: CGRect, screen: NSScreen) {
        countdown.show(on: screen, from: 3, onDone: { [weak self] in
            self?.launchRecording(globalRect: globalRect)
        }, onCancel: {
            Log.coordinator.info("recording cancelled at countdown")
        })
    }

    /// Step 4: launch `screencapture` recording the chosen global rect to a temp
    /// `.mov`. On finish (stop or process exit) the file is finalized,
    /// moved into the Recordings folder, thumbnailed, and stored as a video item.
    private func launchRecording(globalRect: CGRect) {
        guard !isRecording else { return }
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("limiclip-recording-\(UUID().uuidString).mov")
        let started = recorder.start(globalRect: globalRect,
                                     audio: settings.recordAudio,
                                     outputURL: temp) { [weak self] url in
            self?.finishRecording(tempURL: url)
        }
        if started {
            isRecording = true
            menuBar.refreshRecordingState()
            Log.coordinator.info("recording started")
        } else {
            Log.coordinator.error("recording failed to launch")
        }
    }

    /// Stop the in-progress recording. The recorder interrupts `screencapture`,
    /// which finalizes the `.mov` and fires the `onFinish` set in `launchRecording`.
    private func stopRecording() {
        guard isRecording else { return }
        Log.coordinator.info("recording stop requested")
        recorder.stop()
    }

    /// `onFinish` body: move the finalized `.mov` into the user's Recordings
    /// folder, generate a first-frame thumbnail blob, and record a video item.
    /// Clears recording state regardless of outcome. `tempURL` is nil if the
    /// recording failed (launch error, non-zero exit, or missing output).
    private func finishRecording(tempURL: URL?) {
        isRecording = false
        menuBar.refreshRecordingState()
        guard let tempURL else {
            Log.coordinator.error("recording produced no file")
            return
        }
        let folder = RecordingFolder.resolve(bookmark: settings.recordingSaveBookmark)
        let scoped = folder.startAccessingSecurityScopedResource()
        let finalURL: URL
        do {
            finalURL = try RecordingFolder.moveIntoFolder(
                tempURL, folder: folder,
                timestamp: Int64(Date().timeIntervalSince1970))
        } catch {
            if scoped { folder.stopAccessingSecurityScopedResource() }
            Log.coordinator.error("recording move failed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: tempURL)
            return
        }
        if scoped { folder.stopAccessingSecurityScopedResource() }
        Log.coordinator.info("recording saved")

        // Thumbnail + store happen off the main run loop's critical path but on
        // the main actor (store/blobStore are main-actor types).
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.storeRecording(at: finalURL)
        }
    }

    /// Builds the thumbnail (best-effort) and writes the video item.
    private func storeRecording(at url: URL) async {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let byteSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970

        let thumb = await VideoThumbnail.firstFrame(url: url)
        var thumbnailBlobPath: String?
        if let thumb {
            do { thumbnailBlobPath = try blobStore.write(data: thumb.png, fileExtension: "png") }
            catch { Log.coordinator.error("recording thumbnail write failed: \(error.localizedDescription, privacy: .public)") }
        }

        let reference = VideoReference(
            path: url.path,
            name: url.lastPathComponent,
            byteSize: byteSize,
            modifiedAt: Int64(mtime),
            durationSeconds: thumb?.duration ?? 0,
            width: Int(thumb?.size.width ?? 0),
            height: Int(thumb?.size.height ?? 0)
        )
        do {
            let recorded = try store.recordVideo(reference: reference,
                                                 thumbnailBlobPath: thumbnailBlobPath,
                                                 sourceApp: "Screen Recording")
            // On a dedupe hit the new thumbnail isn't adopted; delete it (mirrors
            // the recordImage cleanup in `annotationOutputs().history`).
            if let blobPath = thumbnailBlobPath,
               recorded == nil || (recorded!.blobPath != nil && recorded!.blobPath != blobPath) {
                try? blobStore.delete(relativePath: blobPath)
            }
        } catch {
            Log.coordinator.error("recordVideo failed: \(error.localizedDescription, privacy: .public)")
            if let blobPath = thumbnailBlobPath { try? blobStore.delete(relativePath: blobPath) }
        }
    }

    /// The whole screen as a global top-left rect for `screencapture -R`.
    private static func fullScreenGlobalRect(for screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? frame.height
        return ScreenCaptureGeometry.screencaptureRect(for: frame, primaryHeight: primaryHeight)
    }

    /// A selection rect (top-left view points within `screen`) as a global
    /// top-left rect for `screencapture -R`: the screen's global origin plus the
    /// selection's offset, with the selection's size.
    private static func regionGlobalRect(selection: CGRect, screen: NSScreen) -> CGRect {
        let screenGlobal = fullScreenGlobalRect(for: screen)
        return CGRect(x: screenGlobal.minX + selection.minX,
                      y: screenGlobal.minY + selection.minY,
                      width: selection.width,
                      height: selection.height)
    }

    /// Builds a borderless, transparent, top-level overlay window covering
    /// `screen`. The caller sets `contentView`.
    private func makeFreezeWindow(screen: NSScreen) -> NSWindow {
        let window = ScreenFreezeWindow(contentRect: screen.frame,
                                        styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        window.isFloatingPanel = true
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
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
        reconcileLaunchAtLogin()
        updater.start()

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

    /// Re-asserts the login-item registration at launch if the user previously
    /// enabled it but the service dropped it (e.g. after an app update replaced
    /// the bundle, or the stale-binary trap). This is what keeps "Launch at
    /// Login" sticky across the bundle swaps the auto-updater performs.
    private func reconcileLaunchAtLogin() {
        let intent = settings.defaults.bool(forKey: Settings.Key.launchAtLogin)
        switch LaunchAtLoginReconciler.action(intent: intent, status: LaunchAtLogin.status) {
        case .none:
            break
        case .register:
            do {
                try LaunchAtLogin.setEnabled(true)
                Log.coordinator.info("re-registered launch-at-login on startup")
            } catch {
                Log.coordinator.error("launch-at-login re-register failed: \(error.localizedDescription, privacy: .public)")
            }
        case .needsApproval:
            Log.coordinator.notice("launch-at-login awaiting user approval in System Settings")
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
