// ClipboardManager/UI/Annotation/AnnotationPanel.swift
import AppKit
import SwiftUI

/// A borderless, floating HUD panel that hosts the annotation editor over the
/// screen. Unlike a titled window it has no chrome, is translucent (the view
/// supplies its own visual-effect background), and can be dragged anywhere by
/// its background. It can become key so the editor's local key monitor (⌘C /
/// ⌘S / ⌘⇧S / Esc) receives events.
final class AnnotationPanel: NSPanel {
    init(content: ImageAnnotationView, size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false

        let host = NSHostingView(rootView: content)
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

    /// Esc closes even if the SwiftUI monitor missed it (defensive).
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close(); return }
        super.keyDown(with: event)
    }
}
