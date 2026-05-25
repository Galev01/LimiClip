// ClipboardManager/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("ClipboardManager launched (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
        NSApp.setActivationPolicy(.accessory)  // menu-bar agent, no Dock icon
        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // never terminate when the (non-existent) main window closes
    }
}
