// ClipboardManager/Settings.swift
import Foundation
import AppKit
import SwiftUI
import ServiceManagement

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Single source of truth for user-configurable settings persisted to
/// UserDefaults. Use this struct in coordinators / services where you want
/// to *read* the current values; use the matching `@AppStorage` property
/// wrappers in SwiftUI views where you want to *bind* a control to the
/// underlying default.
struct Settings: @unchecked Sendable {

    enum Key {
        static let appearance = "appearance"
        static let historyLimit = "historyLimit"
        static let retentionDays = "retentionDays"
        static let showHoverPreview = "showHoverPreview"
        static let launchAtLogin = "launchAtLogin"   // tracked-only; service mgmt is source of truth
        static let compactMode = "compactMode"
        static let strictCaptureMode = "strictCaptureMode"
        static let saveScreenshots = "saveScreenshots"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var appearance: AppAppearance {
        get {
            AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "")
                ?? .system
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    var historyLimit: Int {
        get {
            let v = defaults.integer(forKey: Key.historyLimit)
            return v == 0 ? 100 : v
        }
        nonmutating set { defaults.set(newValue, forKey: Key.historyLimit) }
    }

    var retentionDays: Int {
        get {
            let v = defaults.integer(forKey: Key.retentionDays)
            return v == 0 ? 90 : v
        }
        nonmutating set { defaults.set(newValue, forKey: Key.retentionDays) }
    }

    var showHoverPreview: Bool {
        get {
            if defaults.object(forKey: Key.showHoverPreview) == nil { return true }
            return defaults.bool(forKey: Key.showHoverPreview)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.showHoverPreview) }
    }

    var compactMode: Bool {
        get {
            if defaults.object(forKey: Key.compactMode) == nil { return false }
            return defaults.bool(forKey: Key.compactMode)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.compactMode) }
    }

    /// When on, clipboard changes whose source app can't be identified (nil
    /// bundle id) are NOT captured — exclusions fail closed. Default off.
    var strictCaptureMode: Bool {
        get {
            if defaults.object(forKey: Key.strictCaptureMode) == nil { return false }
            return defaults.bool(forKey: Key.strictCaptureMode)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.strictCaptureMode) }
    }

    /// When on, ⌘⇧A screenshots are saved into clipboard history. Default off,
    /// so screenshots reach the clipboard for pasting but aren't persisted.
    var saveScreenshots: Bool {
        get {
            if defaults.object(forKey: Key.saveScreenshots) == nil { return false }
            return defaults.bool(forKey: Key.saveScreenshots)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.saveScreenshots) }
    }
}

// MARK: - Launch-at-login helper (SMAppService, macOS 13+)

enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggles. Returns the new state. Throws if SMAppService rejects the
    /// change (rare in practice).
    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> Bool {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return isEnabled
    }
}
