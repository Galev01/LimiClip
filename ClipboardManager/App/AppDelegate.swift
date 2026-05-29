// ClipboardManager/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("LimiClip launched (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
        NSApp.setActivationPolicy(.accessory)  // menu-bar agent, no Dock icon
        do {
            let coordinator = try AppCoordinator()
            coordinator.start()
            self.coordinator = coordinator
        } catch {
            Log.app.fault("failed to launch coordinator: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "LimiClip couldn't start"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // never terminate when the (non-existent) main window closes
    }
}
