// ClipboardManagerTests/QuickActionDetectorTests.swift
import XCTest
@testable import ClipboardManager

final class QuickActionDetectorTests: XCTestCase {

    // MARK: - Phone number detection

    func testDetectsUSPhone() {
        let actions = QuickActionDetector.detect(in: "+1 555 123 4567")
        XCTAssertEqual(actions.count, 1)
        if case .call(let number) = actions[0] {
            XCTAssertFalse(number.isEmpty)
        } else {
            XCTFail("Expected .call, got \(actions[0])")
        }
    }

    func testDetectsDashedPhone() {
        let actions = QuickActionDetector.detect(in: "555-123-4567")
        XCTAssertEqual(actions.count, 1)
        guard case .call = actions[0] else {
            XCTFail("Expected .call, got \(actions[0])"); return
        }
    }

    func testDetectsParenthesizedPhone() {
        let actions = QuickActionDetector.detect(in: "(555) 123-4567")
        XCTAssertEqual(actions.count, 1)
        guard case .call = actions[0] else {
            XCTFail("Expected .call, got \(actions[0])"); return
        }
    }

    func testPlainTextNotPhone() {
        XCTAssertEqual(QuickActionDetector.detect(in: "hello world"), [])
    }

    func testShortNumberNotPhone() {
        XCTAssertEqual(QuickActionDetector.detect(in: "1234"), [])
    }

    // MARK: - Email detection

    func testDetectsEmail() {
        let actions = QuickActionDetector.detect(in: "user@example.com")
        XCTAssertEqual(actions.count, 1)
        if case .composeEmail(let address) = actions[0] {
            XCTAssertEqual(address, "user@example.com")
        } else {
            XCTFail("Expected .composeEmail, got \(actions[0])")
        }
    }

    func testDetectsEmailWithSubdomain() {
        let actions = QuickActionDetector.detect(in: "gal.lev@xmcyber.com")
        XCTAssertEqual(actions.count, 1)
        guard case .composeEmail(let address) = actions[0] else {
            XCTFail("Expected .composeEmail"); return
        }
        XCTAssertEqual(address, "gal.lev@xmcyber.com")
    }

    func testPlainTextNotEmail() {
        XCTAssertEqual(QuickActionDetector.detect(in: "hello world"), [])
    }

    func testURLSubtypeNotEmail() {
        XCTAssertEqual(QuickActionDetector.detect(in: "https://example.com"), [])
    }

    // MARK: - Hex color detection

    func testDetectsFullHex() {
        let actions = QuickActionDetector.detect(in: "#FF5733")
        XCTAssertEqual(actions.count, 1)
        if case .copyHexColor(let hex) = actions[0] {
            XCTAssertEqual(hex, "#FF5733")
        } else {
            XCTFail("Expected .copyHexColor, got \(actions[0])")
        }
    }

    func testDetectsShortHex() {
        let actions = QuickActionDetector.detect(in: "#fff")
        XCTAssertEqual(actions.count, 1)
        if case .copyHexColor(let hex) = actions[0] {
            XCTAssertEqual(hex, "#fff")
        } else {
            XCTFail("Expected .copyHexColor, got \(actions[0])")
        }
    }

    func testNormalizesHexCase() {
        let actions = QuickActionDetector.detect(in: "#ff5733")
        XCTAssertEqual(actions.count, 1)
        if case .copyHexColor(let hex) = actions[0] {
            XCTAssertEqual(hex, "#ff5733")
        } else {
            XCTFail("Expected .copyHexColor, got \(actions[0])")
        }
    }

    func testPartialHexNotDetected() {
        XCTAssertEqual(QuickActionDetector.detect(in: "some text #FF"), [])
        XCTAssertEqual(QuickActionDetector.detect(in: "#GGGGGG"), [])
        XCTAssertEqual(QuickActionDetector.detect(in: "#12345"), [])
    }

    // MARK: - No false positives

    func testURLStringProducesNoActions() {
        XCTAssertEqual(QuickActionDetector.detect(in: "https://example.com"), [])
    }

    // MARK: - mailto sanitization

    func testSanitizerRejectsControlChars() {
        XCTAssertNil(QuickActionDetector.sanitizedEmailAddress("a@b.com\nBcc:x"))
        XCTAssertNil(QuickActionDetector.sanitizedEmailAddress("a@b.com%0aBcc:x"))
        XCTAssertNil(QuickActionDetector.sanitizedEmailAddress("a@b.com;x"))
        XCTAssertEqual(QuickActionDetector.sanitizedEmailAddress("user@example.com"), "user@example.com")
        XCTAssertEqual(QuickActionDetector.sanitizedEmailAddress("aaaaaaaaaaaaaaaaaaaa@b.com?cc=x"), "aaaaaaaaaaaaaaaaaaaa@b.com")
    }

    func testSanitizerAllowsPlusAddressingAndSubdomains() {
        XCTAssertEqual(QuickActionDetector.sanitizedEmailAddress("user+tag@example.com"), "user+tag@example.com")
        XCTAssertEqual(QuickActionDetector.sanitizedEmailAddress("a@mail.corp.example.com"), "a@mail.corp.example.com")
        XCTAssertNil(QuickActionDetector.sanitizedEmailAddress("user@localhost"), "dot-less domain rejected")
    }

    /// Regression guard: a crafted "email" carrying injected mailto params must
    /// never surface as a composeEmail action with the params intact.
    func testComposeEmailActionNeverCarriesInjectedParams() {
        let actions = QuickActionDetector.detect(in: "victim@example.com?bcc=attacker@evil.com")
        for action in actions {
            if case .composeEmail(let address) = action {
                XCTAssertFalse(address.contains("?"), "address must not carry a query string")
                XCTAssertFalse(address.contains("bcc"), "address must not carry injected bcc")
            }
        }
    }
}
