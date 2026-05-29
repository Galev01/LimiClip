// ClipboardManager/Store/DefaultExclusions.swift
import Foundation

enum DefaultExclusions {
    /// Seeded into the `exclusions` table on first launch. The user can
    /// remove any of these from Preferences.
    ///
    /// LIMITATION: bundle-based exclusion only covers copies that originate from
    /// each app's OWN process. Passwords filled/copied via web-browser AutoFill
    /// (Safari/Chrome) or the iCloud Keychain popover are emitted under the
    /// browser's or system-UI bundle id (NOT `com.apple.Passwords`) and so
    /// cannot be bundle-excluded here. For those the only defense is the
    /// concealed-type handling in `PasteboardMonitor` (and only when the source
    /// app actually marks the pasteboard concealed).
    static let list: [Exclusion] = [
        Exclusion(bundleId: "com.agilebits.onepassword7", name: "1Password 7"),
        Exclusion(bundleId: "com.1password.1password8",   name: "1Password"),
        Exclusion(bundleId: "com.bitwarden.desktop",      name: "Bitwarden"),
        Exclusion(bundleId: "com.apple.keychainaccess",   name: "Keychain Access"),
        Exclusion(bundleId: "com.apple.Passwords",        name: "Passwords"),
        Exclusion(bundleId: "com.lastpass.LastPass",      name: "LastPass"),
        Exclusion(bundleId: "com.dashlane.dashlanephonefinalmac", name: "Dashlane"),
    ]
}
