// ClipboardManager/UI/Preferences/PreferencesWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController {

    private var window: NSWindow?

    /// Brings the preferences window to the front, creating it if necessary.
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: PreferencesView())
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Clipboard Manager — Preferences"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 600, height: 400))
        newWindow.minSize = NSSize(width: 560, height: 380)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.identifier = NSUserInterfaceItemIdentifier("preferences")

        // Make the preferences window force the app to act regular while open,
        // so it can take key focus and respond to ⌘W / ⌘Q like a normal window.
        NSApp.setActivationPolicy(.regular)
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow

        // When the window closes, revert to accessory so we go back to being
        // a pure menu-bar agent.
        let center = NotificationCenter.default
        var token: NSObjectProtocol?
        token = center.addObserver(forName: NSWindow.willCloseNotification, object: newWindow, queue: .main) { [weak self] _ in
            if let token { center.removeObserver(token) }
            NSApp.setActivationPolicy(.accessory)
            self?.window = nil
        }
    }
}
