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

    /// Returns the existing key from Keychain, generating + storing a fresh
    /// one if none exists.
    static func loadOrCreate() throws -> Data {
        if let existing = try loadFromKeychain() {
            return existing
        }
        let key = try generate()
        try storeInKeychain(key)
        return key
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
    }
}
