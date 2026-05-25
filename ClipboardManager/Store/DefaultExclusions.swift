// ClipboardManager/Store/DefaultExclusions.swift
import Foundation

enum DefaultExclusions {
    /// Seeded into the `exclusions` table on first launch. The user can
    /// remove any of these from Preferences (Phase 7).
    static let list: [Exclusion] = [
        Exclusion(bundleId: "com.agilebits.onepassword7", name: "1Password 7"),
        Exclusion(bundleId: "com.1password.1password8",   name: "1Password"),
        Exclusion(bundleId: "com.bitwarden.desktop",      name: "Bitwarden"),
        Exclusion(bundleId: "com.apple.keychainaccess",   name: "Keychain Access"),
        Exclusion(bundleId: "com.lastpass.LastPass",      name: "LastPass"),
        Exclusion(bundleId: "com.dashlane.dashlanephonefinalmac", name: "Dashlane"),
    ]
}
