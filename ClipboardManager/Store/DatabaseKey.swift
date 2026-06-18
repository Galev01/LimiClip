// ClipboardManager/Store/DatabaseKey.swift
import Foundation
import Security
import CryptoKit

/// Manages the AES-256 master key used to encrypt sensitive clipboard data at
/// rest (clipboard fields and image blobs — see `FieldCipher`). The key is
/// generated once and stored in the user's Keychain so subsequent launches can
/// decrypt existing data.
enum DatabaseKey {

    private static let service = "dev.gallev.ClipboardManager.db-key"
    private static let account = "primary"

    /// UserDefaults flag set the first time a key is provisioned. Survives app
    /// rebuilds, so a *missing* Keychain key while this is set means the key
    /// became inaccessible (key mismatch) rather than a fresh install.
    static let provisionedDefaultsKey = "dev.gallev.ClipboardManager.keyProvisioned"

    /// Set true (and logged) when `loadOrCreate` had to mint a new key despite
    /// a previous one having been provisioned — the signal that existing
    /// encrypted data (image blobs) can no longer be decrypted. The coordinator
    /// reads this at startup to surface the condition and prune dead blobs.
    nonisolated(unsafe) private(set) static var didDetectKeyMismatch = false

    enum Failure: Error, CustomStringConvertible {
        case keychain(OSStatus)
        case generation

        var description: String {
            switch self {
            case .keychain(let s): return "Keychain error: \(s)"
            case .generation: return "Failed to generate random key"
            }
        }
    }

    /// Pure decision for what `loadOrCreate` should do, given whether a key is
    /// present in the Keychain and whether one was ever provisioned before.
    enum LoadDecision: Equatable { case useExisting, createFirst, recreateAfterMismatch }

    static func decide(keyPresent: Bool, previouslyProvisioned: Bool) -> LoadDecision {
        if keyPresent { return .useExisting }
        return previouslyProvisioned ? .recreateAfterMismatch : .createFirst
    }

    /// Returns the existing key from Keychain, generating + storing a fresh one
    /// if none exists. If a key was previously provisioned but is now missing,
    /// this is a detected mismatch: it is logged loudly and `didDetectKeyMismatch`
    /// is set so the caller can surface it and prune the now-undecryptable data,
    /// rather than silently minting a new key as if this were a first run.
    static func loadOrCreate(defaults: UserDefaults = .standard) throws -> Data {
        let provisioned = defaults.bool(forKey: provisionedDefaultsKey)
        let existing = try loadFromKeychain()

        switch decide(keyPresent: existing != nil, previouslyProvisioned: provisioned) {
        case .useExisting:
            if !provisioned { defaults.set(true, forKey: provisionedDefaultsKey) }
            return existing!   // decide guarantees non-nil here

        case .createFirst:
            let key = try generate()
            try storeInKeychain(key)
            defaults.set(true, forKey: provisionedDefaultsKey)
            return key

        case .recreateAfterMismatch:
            didDetectKeyMismatch = true
            Log.app.error("DatabaseKey: a key was provisioned before but is now missing from the Keychain — the encryption key changed (most likely a re-signed/stale binary). Existing encrypted history (image blobs) can no longer be decrypted; minting a new key and pruning unreadable items.")
            let key = try generate()
            try storeInKeychain(key)
            return key
        }
    }

    // MARK: - Internals

    private static func generate() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw Failure.generation }
        return Data(bytes)
    }

    private static func loadFromKeychain() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecReturnData as String:      true,
            kSecMatchLimit as String:      kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keychain(status)
        }
    }

    private static func storeInKeychain(_ key: Data) throws {
        let attrs: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecAttrAccessible as String:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:       key,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    /// Removes the key from Keychain. Used by tests; not exposed to users.
    /// After removal, existing encrypted fields and blobs become unreadable.
    static func deleteForTests() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: provisionedDefaultsKey)
        didDetectKeyMismatch = false
    }
}
