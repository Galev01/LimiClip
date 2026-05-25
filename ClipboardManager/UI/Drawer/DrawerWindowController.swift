// ClipboardManager/UI/Drawer/DrawerWindowController.swift
import AppKit

@MainActor
final class DrawerWindowController {
    private let window = DrawerWindow()
    private(set) var isVisible: Bool = false

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDismissRequest),
            name: .drawerDismissRequested, object: nil
        )
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

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.5, 1.0)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(on, display: true)
        }
    }

    func hide() {
        guard isVisible else { return }
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
}
