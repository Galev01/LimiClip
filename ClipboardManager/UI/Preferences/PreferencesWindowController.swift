// ClipboardManager/UI/Preferences/PreferencesWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController {

    private let exclusionsVM: ExclusionsViewModel
    private var window: NSWindow?

    init(exclusionsVM: ExclusionsViewModel) {
        self.exclusionsVM = exclusionsVM
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(
            rootView: PreferencesView(exclusionsVM: exclusionsVM)
        )
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Clipboard Manager — Preferences"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 600, height: 400))
        newWindow.minSize = NSSize(width: 560, height: 380)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.identifier = NSUserInterfaceItemIdentifier("preferences")

        NSApp.setActivationPolicy(.regular)
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow

        let center = NotificationCenter.default
        var token: NSObjectProtocol?
        token = center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            if let token { center.removeObserver(token) }
            NSApp.setActivationPolicy(.accessory)
            self?.window = nil
        }
    }
}
