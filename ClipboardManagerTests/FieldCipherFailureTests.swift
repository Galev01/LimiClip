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

    func testRoundTripStillWorks() throws {
        let a = cipher(7)
        XCTAssertEqual(a.open(try a.seal("hi")), "hi")
        XCTAssertEqual(a.open(try a.seal(Data("hi".utf8))), Data("hi".utf8))
    }
}
