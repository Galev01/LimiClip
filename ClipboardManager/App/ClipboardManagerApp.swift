// ClipboardManager/App/ClipboardManagerApp.swift
import SwiftUI

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Headless: menu bar only, no Settings or main window.
        // Settings window will be added in Phase 7.
        SwiftUI.Settings { EmptyView() }
    }
}
