// ClipboardManager/UI/Drawer/DrawerWindowController.swift
import AppKit

@MainActor
final class DrawerWindowController {
    private let window: DrawerWindow
    private(set) var isVisible: Bool = false
    nonisolated(unsafe) private var clickOutsideMonitor: Any?
    private let injector: PasteInjector
    private let store: ClipboardStore
    private let viewModel: ClipboardViewModel

    /// Set by the coordinator after construction (the coordinator can't pass a
    /// `self`-capturing closure into its own `let` properties during init).
    var onAnnotate: ((Item) -> Void)?

    init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore, injector: PasteInjector) {
        self.injector = injector
        self.store = store
        self.viewModel = viewModel

        var pasteHandler: ((Item, Bool) -> Void)!
        var copyHandler: ((Item) -> Void)!
        var deleteHandler: ((Item) -> Void)!
        var openURLHandler: ((Item) -> Void)!
        var revealHandler: ((Item) -> Void)!
        var pinHandler: ((Item, Bool) -> Void)!
        var annotateHandler: ((Item) -> Void)!
        var playVideoHandler: ((Item) -> Void)!
        var clearAllHandler: (() -> Void)!

        self.window = DrawerWindow(
            viewModel: viewModel, blobStore: blobStore, store: store,
            onPaste: { item, asPlain in pasteHandler(item, asPlain) },
            onCopy: { item in copyHandler(item) },
            onDelete: { item in deleteHandler(item) },
            onOpenURL: { item in openURLHandler(item) },
            onRevealInFinder: { item in revealHandler(item) },
            onPin: { item, pinned in pinHandler(item, pinned) },
            onAnnotate: { item in annotateHandler(item) },
            onPlayVideo: { item in playVideoHandler(item) },
            onClearAll: { clearAllHandler() },
            accessibilityCheck: { [injector] in injector.hasAccessibilityPermission }
        )

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDismissRequest),
            name: .drawerDismissRequested, object: nil
        )

        pasteHandler = { [weak self] item, asPlain in self?.handlePaste(item: item, asPlain: asPlain) }
        copyHandler = { [weak self] item in self?.handleCopy(item: item) }
        deleteHandler = { [weak self] item in self?.handleDelete(item: item) }
        openURLHandler = { [weak self] item in self?.handleOpenURL(item: item) }
        revealHandler = { [weak self] item in self?.handleReveal(item: item) }
        pinHandler = { [weak self] item, pinned in self?.handlePin(item: item, pinned: pinned) }
        annotateHandler = { [weak self] item in self?.onAnnotate?(item) }
        playVideoHandler = { [weak self] item in self?.handlePlayVideo(item: item) }
        clearAllHandler = { [weak self] in self?.handleClearAll() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @objc private func handleDismissRequest() { hide() }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
        // Fresh slate on every open: a query left over from the previous
        // open hides items, and a still-focused search field swallows the
        // arrow keys (DrawerWindow.keyDown never sees them).
        viewModel.resetTransientUIState()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            Log.drawer.error("no screen available")
            return
        }
        let visible = screen.visibleFrame  // excludes menu bar + Dock
        let off = DrawerGeometry.offScreenFrame(in: visible, height: DrawerWindow.drawerHeight)
        let on = DrawerGeometry.onScreenFrame(in: visible, height: DrawerWindow.drawerHeight)

        window.setFrame(off, display: false)
        window.orderFrontRegardless()
        window.makeKey()
        isVisible = true

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible else { return }
                // Mouse location is in screen coordinates; window.frame is in screen coordinates too.
                let mouse = NSEvent.mouseLocation
                if !self.window.frame.contains(mouse) {
                    Log.drawer.info("click outside drawer — dismissing")
                    self.hide()
                }
            }
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.5, 1.0)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(on, display: true)
        }
    }

    func hide(animated: Bool = true) {
        guard isVisible else { return }
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        // The paste path needs the panel GONE (and key status resigned)
        // before the synthesized ⌘V fires — an animated slide keeps the
        // panel key for its full 0.28s, and the keystroke lands in the
        // dying drawer instead of the target app.
        guard animated, let screen = window.screen ?? NSScreen.main else {
            window.orderOut(nil)
            isVisible = false
            return
        }
        let off = DrawerGeometry.offScreenFrame(in: screen.visibleFrame, height: DrawerWindow.drawerHeight)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.7, 0.4)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(off, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.window.orderOut(nil)
                self?.isVisible = false
            }
        })
    }

    private func handlePaste(item: Item, asPlain: Bool) {
        do {
            try injector.writeToPasteboard(item: item, asPlainText: asPlain)
        } catch {
            Log.drawer.error("paste write failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Instant dismissal: the panel must resign key before ⌘V fires or
        // the keystroke is swallowed by the drawer itself (see hide()).
        hide(animated: false)
        // Silent check only — the drawer's banner is the single source of
        // permission guidance, so we don't spam the system dialog on every
        // paste. The item is on the clipboard either way; the user can
        // paste manually until they grant Accessibility via the banner.
        guard injector.hasAccessibilityPermission else {
            Log.drawer.info("paste injection skipped — Accessibility permission missing")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.injector.synthesizePasteKeystroke()
        }
    }

    private func handleCopy(item: Item) {
        do { try injector.writeToPasteboard(item: item) }
        catch { Log.drawer.error("copy write failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func handleDelete(item: Item) {
        guard let id = item.id else { return }
        do { try store.softDelete(itemId: id) }
        catch { Log.drawer.error("delete failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func handlePin(item: Item, pinned: Bool) {
        guard let id = item.id else { return }
        do { try store.setPinned(itemId: id, pinned: pinned) }
        catch { Log.drawer.error("pin failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func handleOpenURL(item: Item) {
        guard item.subtype == TextSubtype.url.rawValue,
              let url = URL(string: item.body) else { return }
        NSWorkspace.shared.open(url)
        hide()
    }

    private func handlePlayVideo(item: Item) {
        guard item.kind == "video",
              let ref = try? VideoReference.decodingJSON(item.body) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: ref.path))
        hide()
    }

    private func handleReveal(item: Item) {
        let path: String?
        switch item.kind {
        case "file":  path = (try? FileReference.decodingJSON(item.body))?.path
        case "video": path = (try? VideoReference.decodingJSON(item.body))?.path
        default:      path = nil
        }
        guard let path else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        hide()
    }

    private func handleClearAll() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "All items will be removed. Pinned items will be kept."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.clearAll()
        } catch {
            Log.drawer.error("clearAll failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
