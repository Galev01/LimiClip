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
        static let launchAtLogin = "launchAtLogin"   // persisted user intent; reconciled against SMAppService at launch
        static let compactMode = "compactMode"
        static let strictCaptureMode = "strictCaptureMode"
        static let saveScreenshots = "saveScreenshots"
        static let captureScreenshotFiles = "captureScreenshotFiles"
        static let annotationSaveFolder = "annotationSaveFolder"
        static let recordingSaveFolder = "recordingSaveFolder"
        static let recordAudio = "recordAudio"
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

    /// When on, macOS screenshots saved as files to the screenshot folder
    /// (⌘⇧4, default behaviour) are imported into clipboard history. Default
    /// on. Independent of `saveScreenshots`, which governs the in-app ⌘⇧A
    /// clipboard screenshot.
    var captureScreenshotFiles: Bool {
        get {
            if defaults.object(forKey: Key.captureScreenshotFiles) == nil { return true }
            return defaults.bool(forKey: Key.captureScreenshotFiles)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.captureScreenshotFiles) }
    }

    /// Security-scoped bookmark to the folder where flattened annotated images
    /// are saved. Nil when unset (callers fall back to ~/Pictures).
    var annotationSaveBookmark: Data? {
        get { defaults.data(forKey: Key.annotationSaveFolder) }
        nonmutating set { defaults.set(newValue, forKey: Key.annotationSaveFolder) }
    }

    /// Security-scoped bookmark to the folder where screen recordings are saved.
    /// Nil when unset (callers fall back to ~/Movies).
    var recordingSaveBookmark: Data? {
        get { defaults.data(forKey: Key.recordingSaveFolder) }
        nonmutating set { defaults.set(newValue, forKey: Key.recordingSaveFolder) }
    }

    /// When on, screen recordings include microphone audio (`screencapture -g`).
    /// Default off (mirror `saveScreenshots`), so recordings are silent unless
    /// the user opts in and grants the mic prompt.
    var recordAudio: Bool {
        get {
            if defaults.object(forKey: Key.recordAudio) == nil { return false }
            return defaults.bool(forKey: Key.recordAudio)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.recordAudio) }
    }
}

// MARK: - Launch-at-login helper (SMAppService, macOS 13+)

enum LaunchAtLogin {

    /// User-visible result of a toggle, so callers can react to the macOS case
    /// where registration succeeds but the login item still needs the user to
    /// approve it in System Settings → General → Login Items.
    enum Outcome: Equatable { case enabled, requiresApproval, disabled }

    /// The real service status. `register()` can succeed yet leave the status
    /// at `.requiresApproval`, so callers must inspect this rather than assume
    /// "no throw" means "enabled".
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// Maps a raw service status to the user-facing outcome.
    static func outcome(for status: SMAppService.Status) -> Outcome {
        switch status {
        case .enabled:         return .enabled
        case .requiresApproval: return .requiresApproval
        default:               return .disabled   // .notRegistered, .notFound
        }
    }

    /// Toggles the login item and persists the user's *intent* to
    /// `Settings.Key.launchAtLogin` so startup reconciliation can re-assert it
    /// after the service drops the registration (app update / move). Returns the
    /// resulting outcome; on `.requiresApproval` the caller should keep the
    /// toggle on and prompt the user to approve. Throws if SMAppService rejects
    /// the change (rare in practice).
    @discardableResult
    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) throws -> Outcome {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        defaults.set(enabled, forKey: Settings.Key.launchAtLogin)
        return outcome(for: status)
    }

    /// Opens System Settings to the Login Items pane so the user can approve a
    /// `.requiresApproval` registration.
    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

// MARK: - Launch-at-login startup reconciliation

/// Pure decision logic for reconciling the persisted user intent with the
/// current service status at app launch. Extracted as a free function so it can
/// be unit-tested without touching the real `SMAppService`.
enum LaunchAtLoginReconciler {

    enum Action: Equatable {
        case none           // intent satisfied (or user doesn't want it)
        case register       // intent on but service forgot — re-register
        case needsApproval  // intent on but macOS is waiting on the user
    }

    static func action(intent: Bool, status: SMAppService.Status) -> Action {
        guard intent else { return .none }
        switch status {
        case .enabled:                   return .none
        case .notRegistered, .notFound:  return .register
        case .requiresApproval:          return .needsApproval
        @unknown default:                return .none
        }
    }
}
