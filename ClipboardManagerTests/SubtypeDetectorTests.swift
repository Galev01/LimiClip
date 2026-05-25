import XCTest
@testable import ClipboardManager

final class SubtypeDetectorTests: XCTestCase {

    func testDetectsURL() {
        XCTAssertEqual(SubtypeDetector.detect("https://example.com"), .url)
        XCTAssertEqual(SubtypeDetector.detect("http://example.com/path?q=1"), .url)
        XCTAssertEqual(SubtypeDetector.detect("https://github.com/user/repo/pull/42"), .url)
    }

    func testRejectsNonURLTextThatLooksUrlish() {
        XCTAssertNotEqual(SubtypeDetector.detect("see https://example.com for details"), .url)
        XCTAssertNotEqual(SubtypeDetector.detect("https://x"), .url) // too short / no TLD
    }

    func testDetectsJSON() {
        XCTAssertEqual(SubtypeDetector.detect("{\"a\": 1}"), .json)
        XCTAssertEqual(SubtypeDetector.detect("[1, 2, 3]"), .json)
        XCTAssertEqual(SubtypeDetector.detect("  {\n  \"name\": \"x\"\n}  "), .json)
    }

    func testRejectsInvalidJSON() {
        XCTAssertNotEqual(SubtypeDetector.detect("{a: 1}"), .json)
        XCTAssertNotEqual(SubtypeDetector.detect("just curly { and brackets ]"), .json)
    }

    func testDetectsCode() {
        XCTAssertEqual(SubtypeDetector.detect("func foo() {\n    return 42\n}"), .code)
        XCTAssertEqual(SubtypeDetector.detect("def hello():\n    print('hi')"), .code)
        XCTAssertEqual(SubtypeDetector.detect("const x = await fetch('/api');"), .code)
        XCTAssertEqual(SubtypeDetector.detect("SELECT * FROM users WHERE id = 1;"), .code)
    }

    func testPlainFallback() {
        XCTAssertEqual(SubtypeDetector.detect("Hey team, can we meet Thursday?"), .plain)
        XCTAssertEqual(SubtypeDetector.detect("1600 Amphitheatre Parkway"), .plain)
    }

    func testEmptyAndWhitespaceArePlain() {
        XCTAssertEqual(SubtypeDetector.detect(""), .plain)
        XCTAssertEqual(SubtypeDetector.detect("   \n  "), .plain)
    }
}
