// ClipboardManager/UI/Compact/CompactPopupWindowController.swift
import AppKit

@MainActor
final class CompactPopupWindowController {
    private let window: CompactPopupWindow
    private let viewModel: ClipboardViewModel
    private let injector: PasteInjector
    private let store: ClipboardStore
    private(set) var isVisible: Bool = false
    private var clickOutsideMonitor: Any?

    init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore, injector: PasteInjector) {
        self.viewModel = viewModel
        self.injector = injector
        self.store = store

        var pasteHandler: ((Item) -> Void)!

        self.window = CompactPopupWindow(
            rootView: CompactPopupView(
                viewModel: viewModel,
                onPaste: { item in pasteHandler(item) },
                blobStore: blobStore
            )
        )

        pasteHandler = { [weak self] item in self?.handlePaste(item: item) }
    }

    func toggle(near cursor: NSPoint) {
        isVisible ? hide() : show(near: cursor)
    }

    func show(near cursor: NSPoint) {
        guard !isVisible else { return }
        let itemCount = min(10, viewModel.items.count)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
                     ?? NSScreen.main
                     ?? NSScreen.screens[0]
        let frame = CompactPopupGeometry.frame(near: cursor, itemCount: itemCount, in: screen.visibleFrame)

        window.setFrame(frame, display: false)
        window.orderFrontRegardless()
        window.makeKey()
        isVisible = true

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible else { return }
                if !self.window.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        window.orderOut(nil)
        isVisible = false
    }

    private func handlePaste(item: Item) {
        do {
            try injector.writeToPasteboard(item: item, asPlainText: false)
        } catch {
            Log.drawer.error("compact paste write failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        hide()
        guard injector.hasAccessibilityPermission else {
            Log.drawer.info("compact paste skipped — Accessibility permission missing")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.injector.synthesizePasteKeystroke()
        }
    }
}
