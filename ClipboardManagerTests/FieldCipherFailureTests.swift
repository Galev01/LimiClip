import XCTest
import CryptoKit
@testable import ClipboardManager

final class FieldCipherFailureTests: XCTestCase {

    private func cipher(_ seed: UInt8) -> FieldCipher {
        FieldCipher(masterKeyData: Data(repeating: seed, count: 32))
    }

    func testStringSealedWithWrongKeyOpensToEmptyNotCiphertext() throws {
        let a = cipher(1)
        let b = cipher(2)
        let sealed = try a.seal("secret")
        let opened = b.open(sealed)
        XCTAssertEqual(opened, "", "wrong-key open must not leak ciphertext")
        XCTAssertFalse(opened.hasPrefix(FieldCipher.stringPrefix))
    }

    func testStringPlaintextPassesThroughUnchanged() {
        let a = cipher(1)
        XCTAssertEqual(a.open("plain text"), "plain text")
    }

    func testBlobSealedWithWrongKeyOpensToEmptyNotCiphertext() throws {
        let a = cipher(1)
        let b = cipher(2)
        let sealed = try a.seal(Data("payload".utf8))
        let opened = b.open(sealed)
        XCTAssertTrue(opened.isEmpty, "wrong-key blob open must not leak ciphertext")
    }

    func testBlobLegacyPlaintextPassesThroughUnchanged() {
        let a = cipher(1)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(a.open(png), png)
    }

    /// Regression: the throwing blob-open must SURFACE a decrypt failure for a
    /// sealed blob whose key no longer matches, rather than silently swallowing
    /// it into empty `Data()` (the live-install gray-placeholder root cause).
    func testThrowingBlobOpenSurfacesWrongKeyFailure() throws {
        let a = cipher(1)
        let b = cipher(2)
        let sealed = try a.seal(Data("payload".utf8))
        XCTAssertThrowsError(try b.open(sealedBlob: sealed)) { error in
            XCTAssertEqual(error as? FieldCipher.Failure, .openFailed)
        }
    }

    /// The throwing open still passes legacy plaintext (no GCM magic) through.
    func testThrowingBlobOpenPassesLegacyPlaintext() throws {
        let a = cipher(1)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(try a.open(sealedBlob: png), png)
    }

    func testRoundTripStillWorks() throws {
        let a = cipher(7)
        XCTAssertEqual(a.open(try a.seal("hi")), "hi")
        XCTAssertEqual(a.open(try a.seal(Data("hi".utf8))), Data("hi".utf8))
    }
}
