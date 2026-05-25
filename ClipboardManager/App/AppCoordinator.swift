// ClipboardManager/App/AppCoordinator.swift
import AppKit

@MainActor
final class AppCoordinator {
    private let menuBar: MenuBarController
    private let drawer = DrawerWindowController()
    private let hotkey: HotkeyService

    init() {
        // Pre-declare locals so the closures can capture `drawer` safely.
        let drawer = self.drawer

        self.menuBar = MenuBarController { drawer.toggle() }
        self.hotkey = HotkeyService { drawer.toggle() }
    }

    func start() {
        Log.coordinator.info("coordinator starting")
        hotkey.start()
    }
}
