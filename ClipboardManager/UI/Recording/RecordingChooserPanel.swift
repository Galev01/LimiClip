// ClipboardManager/UI/Recording/RecordingChooserPanel.swift
import AppKit
import SwiftUI

/// What the user picked in the recording chooser.
enum RecordingChoice {
    case region
    case fullScreen
    case cancel
}

/// A small borderless, nonactivating HUD panel — the first step of the screen
/// recording flow. It floats centered on the target screen and offers three
/// choices: record a Region, record the Full Screen, or Cancel. Built like
/// `AnnotationPanel`/`ScreenFreezeWindow` so it behaves correctly in this
/// menu-bar-only (LSUIElement) app: it can become key so its Esc key handler
/// fires, sits above normal windows, and joins all spaces.
///
/// Exercised by the AppCoordinator orchestration (plan Task 6); here it just
/// needs to build and present a choice via `show`.
@MainActor
final class RecordingChooserPanel {
    private var panel: ChooserPanel?

    /// Presents the chooser centered on the screen under the mouse (falling back
    /// to the main screen). `onChoice` is invoked exactly once, on the main
    /// actor, after which the panel is dismissed. Esc / clicking Cancel reports
    /// `.cancel`.
    func show(onChoice: @escaping @MainActor (RecordingChoice) -> Void) {
        // Don't stack panels if one is already up.
        guard panel == nil else { return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main

        let size = NSSize(width: 320, height: 168)
        let p = ChooserPanel(size: size)

        // Report a choice at most once, then tear the panel down.
        var didReport = false
        let finish: @MainActor (RecordingChoice) -> Void = { [weak self] choice in
            guard !didReport else { return }
            didReport = true
            self?.dismiss()
            onChoice(choice)
        }

        let view = RecordingChooserView(
            onRegion: { finish(.region) },
            onFullScreen: { finish(.fullScreen) },
            onCancel: { finish(.cancel) }
        )
        p.onEscape = { finish(.cancel) }
        p.contentView = NSHostingView(rootView: view)

        if let screen {
            let f = screen.frame
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
        } else {
            p.center()
        }

        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p
        Log.coordinator.info("recording chooser shown")
    }

    /// Tears down the panel if showing. Safe to call repeatedly.
    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Borderless nonactivating panel hosting the chooser. Can become key so Esc is
/// delivered even if a SwiftUI monitor missed it.
private final class ChooserPanel: NSPanel {
    var onEscape: (() -> Void)?

    init(size: NSSize) {
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
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return }   // Esc
        super.keyDown(with: event)
    }
}

/// The three-button chooser content. Supplies its own HUD background (the panel
/// itself is clear), matching the annotation tool drawer's look.
private struct RecordingChooserView: View {
    var onRegion: () -> Void
    var onFullScreen: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Record Screen")
                .font(.headline)

            HStack(spacing: 14) {
                choiceButton(title: "Region", systemImage: "rectangle.dashed", action: onRegion)
                choiceButton(title: "Full Screen", systemImage: "rectangle.inset.filled", action: onFullScreen)
            }

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
    }

    private func choiceButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .regular))
                Text(title)
                    .font(.subheadline)
            }
            .frame(width: 110, height: 78)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.10))
        )
    }
}
