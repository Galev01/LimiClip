import XCTest
import CryptoKit
@testable import ClipboardManager

final class FieldCipherTests: XCTestCase {

    private func makeCipher(byte: UInt8 = 1) -> FieldCipher {
        FieldCipher(masterKeyData: Data(repeating: byte, count: 32))
    }

    // MARK: - String sealing

    func testStringRoundtripReturnsOriginal() {
        let cipher = makeCipher()
        let secret = "hunter2 — my password"
        let sealed = try! cipher.seal(secret)
        XCTAssertEqual(cipher.open(sealed), secret)
    }

    func testSealedStringIsNotPlaintext() {
        let cipher = makeCipher()
        let plaintext = "super secret token"
        let sealed = try! cipher.seal(plaintext)
        XCTAssertFalse(sealed.contains(plaintext), "ciphertext must not embed the plaintext")
        XCTAssertNotEqual(sealed, plaintext)
        XCTAssertTrue(cipher.isSealed(sealed), "sealed values must be recognizable as sealed")
    }

    func testSealIsNonDeterministic() {
        let cipher = makeCipher()
        let a = try! cipher.seal("same input")
        let b = try! cipher.seal("same input")
        XCTAssertNotEqual(a, b, "GCM uses a fresh nonce each time, so ciphertext must differ")
        XCTAssertEqual(cipher.open(a), "same input")
        XCTAssertEqual(cipher.open(b), "same input")
    }

    func testOpenLeavesLegacyPlaintextUntouched() {
        let cipher = makeCipher()
        // Rows written before encryption have no prefix — must read back verbatim.
        let legacy = "plain old clipboard text"
        XCTAssertFalse(cipher.isSealed(legacy))
        XCTAssertEqual(cipher.open(legacy), legacy)
    }

    func testWrongKeyCannotDecrypt() {
        let sealed = try! makeCipher(byte: 1).seal("classified")
        // A different key must NOT yield the plaintext; graceful fallback returns input.
        let other = makeCipher(byte: 2)
        XCTAssertNotEqual(other.open(sealed), "classified")
    }

    // MARK: - Blob sealing

    func testBlobRoundtripReturnsOriginalBytes() {
        let cipher = makeCipher()
        let bytes = Data((0..<512).map { UInt8($0 % 256) })
        let sealed = try! cipher.seal(bytes)
        XCTAssertNotEqual(sealed, bytes)
        XCTAssertEqual(cipher.open(sealed), bytes)
    }

    func testOpenLeavesLegacyPlaintextBlobUntouched() {
        let cipher = makeCipher()
        // A real PNG header — legacy unencrypted blob, must pass through unchanged.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        XCTAssertEqual(cipher.open(png), png)
    }

    // MARK: - Dedup hash

    func testDedupHashIsDeterministic() {
        let cipher = makeCipher()
        XCTAssertEqual(cipher.dedupHash("repeat me"), cipher.dedupHash("repeat me"))
    }

    func testDedupHashDiffersByContent() {
        let cipher = makeCipher()
        XCTAssertNotEqual(cipher.dedupHash("alpha"), cipher.dedupHash("beta"))
    }

    func testDedupHashIsKeyedNotPlainSHA256() {
        // The whole point: an attacker without the key can't brute-force short
        // secrets by precomputing SHA256. So our hash must differ from raw SHA256.
        let cipher = makeCipher()
        let plainSHA = SHA256.hash(data: Data("1234".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertNotEqual(cipher.dedupHash("1234"), plainSHA)
    }

    func testDedupHashDiffersByKey() {
        XCTAssertNotEqual(makeCipher(byte: 1).dedupHash("x"), makeCipher(byte: 2).dedupHash("x"))
    }
}
