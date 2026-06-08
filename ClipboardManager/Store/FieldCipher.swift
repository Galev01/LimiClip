// ClipboardManager/Store/FieldCipher.swift
import Foundation
import CryptoKit

/// Encrypts sensitive clipboard fields and blob bytes at rest, and derives a
/// keyed dedup hash — all from the single master key held in `DatabaseKey`.
///
/// Three independent sub-keys are derived from the master via HKDF so the same
/// bytes are never reused across cryptographic roles (field encryption, blob
/// encryption, dedup HMAC). Sealing uses AES-256-GCM, which authenticates as
/// well as encrypts.
struct FieldCipher: Sendable {

    private let stringKey: SymmetricKey
    private let blobKey: SymmetricKey
    private let macKey: SymmetricKey

    /// Prefix on every sealed string — lets us distinguish ciphertext from the
    /// plaintext rows written before encryption existed (used by reads + the
    /// one-time migration). A real clipboard string that happens to start with
    /// this is harmless: `open` falls back to returning it verbatim.
    static let stringPrefix = "gcm1:"
    /// Magic header on every sealed blob file, same purpose. A legacy PNG starts
    /// with `\x89PNG`, never this, so old blobs pass through `open` unchanged.
    static let blobMagic = Data("GCM1".utf8)

    init(masterKey: SymmetricKey) {
        func derive(_ info: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(
                inputKeyMaterial: masterKey,
                info: Data(info.utf8),
                outputByteCount: 32
            )
        }
        stringKey = derive("limiclip-field-enc-v1")
        blobKey   = derive("limiclip-blob-enc-v1")
        macKey    = derive("limiclip-dedup-hmac-v1")
    }

    init(masterKeyData: Data) {
        self.init(masterKey: SymmetricKey(data: masterKeyData))
    }

    // MARK: - String fields

    func seal(_ plaintext: String) throws -> String {
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: stringKey)
        guard let combined = box.combined else { throw Failure.sealFailed }
        return Self.stringPrefix + combined.base64EncodedString()
    }

    /// Inverse of `seal`. Returns unprefixed (legacy plaintext) input verbatim.
    /// If the sealed prefix is present but decryption fails (wrong key,
    /// corruption, or tampering), returns empty string — never the ciphertext.
    func open(_ stored: String) -> String {
        guard stored.hasPrefix(Self.stringPrefix) else { return stored }
        let b64 = String(stored.dropFirst(Self.stringPrefix.count))
        guard let data = Data(base64Encoded: b64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: stringKey),
              let text = String(data: opened, encoding: .utf8)
        else {
            // Sealed prefix present but decryption failed: corruption, wrong
            // key, or tampering. Never return the ciphertext to the UI.
            Log.app.warning("FieldCipher: sealed string failed to open; returning empty")
            return ""
        }
        return text
    }

    func isSealed(_ stored: String) -> Bool {
        stored.hasPrefix(Self.stringPrefix)
    }

    // MARK: - Blob bytes

    func seal(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: blobKey)
        guard let combined = box.combined else { throw Failure.sealFailed }
        return Self.blobMagic + combined
    }

    func open(_ data: Data) -> Data {
        guard data.prefix(Self.blobMagic.count) == Self.blobMagic else { return data }
        let body = Data(data.dropFirst(Self.blobMagic.count))
        guard let box = try? AES.GCM.SealedBox(combined: body),
              let opened = try? AES.GCM.open(box, using: blobKey)
        else {
            Log.app.warning("FieldCipher: sealed blob failed to open; returning empty")
            return Data()
        }
        return opened
    }

    // MARK: - Dedup hash

    /// Keyed HMAC-SHA256, hex. Deterministic (so content-hash dedup still works)
    /// but, unlike a raw SHA256, not precomputable by an attacker who lacks the
    /// key — so short secrets can't be brute-forced from the stored hash.
    func dedupHash(_ content: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(content.utf8), using: macKey)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    enum Failure: Error { case sealFailed }
}
