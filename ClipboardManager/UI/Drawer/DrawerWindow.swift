// ClipboardManager/UI/Drawer/DrawerWindow.swift
import AppKit
import SwiftUI

final class DrawerWindow: NSPanel {
    static let drawerHeight: CGFloat = 300

    private let viewModel: ClipboardViewModel
    private let store: ClipboardStore

    init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore) {
        self.viewModel = viewModel
        self.store = store
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let host = NSHostingView(rootView: DrawerView(viewModel: viewModel, blobStore: blobStore))
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let isCommand = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 53:   // Esc
            NotificationCenter.default.post(name: .drawerDismissRequested, object: nil)
        case 123:  // Left arrow
            Task { @MainActor in viewModel.moveFocus(by: -1) }
        case 124:  // Right arrow
            Task { @MainActor in viewModel.moveFocus(by: +1) }
        case 117, 51:  // forward delete, delete (backspace)
            if let id = viewModel.currentItem?.id {
                Task { @MainActor in
                    do { try store.softDelete(itemId: id) }
                    catch { Log.drawer.error("delete failed: \(error.localizedDescription, privacy: .public)") }
                }
            }
        case 18...26 where isCommand:
            // ⌘1 = keyCode 18, ⌘2 = 19, ... ⌘9 = 25.
            let n = Int(event.keyCode) - 18
            Task { @MainActor in viewModel.jumpTo(index: n) }
        default:
            super.keyDown(with: event)
        }
    }
}

extension Notification.Name {
    static let drawerDismissRequested = Notification.Name("DrawerDismissRequested")
}
