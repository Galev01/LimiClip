// ClipboardManager/UI/Drawer/DrawerWindowController.swift
import AppKit

@MainActor
final class DrawerWindowController {
    private let window: DrawerWindow
    private(set) var isVisible: Bool = false
    private var clickOutsideMonitor: Any?
    private let injector: PasteInjector
    private let store: ClipboardStore

    init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore, injector: PasteInjector) {
        self.injector = injector
        self.store = store

        var pasteHandler: ((Item, Bool) -> Void)!
        var copyHandler: ((Item) -> Void)!
        var deleteHandler: ((Item) -> Void)!
        var openURLHandler: ((Item) -> Void)!
        var revealHandler: ((Item) -> Void)!

        self.window = DrawerWindow(
            viewModel: viewModel, blobStore: blobStore, store: store,
            onPaste: { item, asPlain in pasteHandler(item, asPlain) },
            onCopy: { item in copyHandler(item) },
            onDelete: { item in deleteHandler(item) },
            onOpenURL: { item in openURLHandler(item) },
            onRevealInFinder: { item in revealHandler(item) },
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
    }

    @objc private func handleDismissRequest() { hide() }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
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

    func hide() {
        guard isVisible else { return }
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        guard let screen = window.screen ?? NSScreen.main else {
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
        hide()
        // Trigger the macOS Accessibility prompt the first time the user
        // tries to paste. If they grant it, the keystroke synthesis 80ms
        // later will land in the target app. If they decline, the item is
        // still on the clipboard for manual ⌘V.
        let trusted = injector.promptForAccessibilityIfNeeded()
        if !trusted {
            Log.drawer.info("paste injection skipped — Accessibility permission missing or pending")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
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

    private func handleOpenURL(item: Item) {
        guard item.subtype == TextSubtype.url.rawValue,
              let url = URL(string: item.body) else { return }
        NSWorkspace.shared.open(url)
        hide()
    }

    private func handleReveal(item: Item) {
        guard item.kind == "file",
              let ref = try? FileReference.decodingJSON(item.body) else { return }
        let url = URL(fileURLWithPath: ref.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        hide()
    }
}
