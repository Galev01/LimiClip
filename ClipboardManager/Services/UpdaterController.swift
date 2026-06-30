// ClipboardManager/Services/UpdaterController.swift
import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater. Owns the updater for the
/// app's lifetime, exposes a manual "Check for Updates…" entry point, and the
/// automatic-check toggle for Preferences.
///
/// Feed + signing live in Info.plist (`SUFeedURL`, `SUPublicEDKey`,
/// `SUVerifyUpdateBeforeExtraction`); Sparkle verifies the EdDSA signature on
/// the downloaded DMG before installing.
@MainActor
final class UpdaterController: NSObject {

    /// Sentinel shipped in Info.plist until the `generate_keys` bootstrap fills
    /// in the real EdDSA public key. While present, the updater stays inert so
    /// the app is shippable pre-bootstrap without misconfiguration alerts.
    private static let placeholderKey = "REPLACE_WITH_GENERATED_ED25519_PUBLIC_KEY"

    private let controller: SPUStandardUpdaterController
    // Retained here because the standard user driver holds its delegate weakly.
    private let driverDelegate = GentleUpdaterDriverDelegate()
    /// True once a real EdDSA public key is configured (post-bootstrap).
    private let isConfigured: Bool

    override init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isConfigured = (key?.isEmpty == false) && key != Self.placeholderKey
        // startingUpdater: false — we start explicitly in `start()` once the
        // app has finished launching. Constructing without starting does not
        // validate the key, so this is safe even when unconfigured.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: driverDelegate
        )
        super.init()
    }

    func start() {
        guard isConfigured else {
            Log.app.notice("Sparkle updater not started — SUPublicEDKey not configured (run generate_keys bootstrap)")
            return
        }
        controller.startUpdater()
        Log.app.info("Sparkle updater started")
    }

    /// Triggers a user-initiated check (wired to the menu-bar item). This path
    /// is foreground/interactive, so the update dialog shows and focuses
    /// normally even for an accessory app.
    func checkForUpdates() {
        guard isConfigured else {
            Log.app.notice("check for updates requested but updater is not configured")
            return
        }
        controller.checkForUpdates(nil)
    }

    /// Bound to the "Automatically check for updates" toggle in Preferences.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

/// Makes scheduled (background) update reminders surface correctly for a
/// dockless `.accessory` app. Sparkle 2.2+ intentionally won't let a scheduled
/// alert steal focus from a background app, so without this delegate the prompt
/// can appear behind other windows and be missed. We opt into gentle reminders
/// and bring the app forward when Sparkle is about to show an update.
private final class GentleUpdaterDriverDelegate: NSObject, SPUStandardUserDriverDelegate {

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            // Return to menu-bar-only mode once the update session ends.
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
