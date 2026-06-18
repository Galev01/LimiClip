import XCTest
@testable import ClipboardManager

final class ChainCopyTests: XCTestCase {

    func test_appendsWithSpace() {
        XCTAssertEqual(ChainCopyService.combine(previous: "hi", addition: "mister"), "hi mister")
    }

    func test_accumulatesAcrossChains() {
        let once = ChainCopyService.combine(previous: "hi", addition: "mister")
        XCTAssertEqual(ChainCopyService.combine(previous: once, addition: "there"), "hi mister there")
    }

    func test_emptyPreviousReturnsAddition() {
        XCTAssertEqual(ChainCopyService.combine(previous: "", addition: "mister"), "mister")
    }

    func test_emptyAdditionReturnsPrevious() {
        XCTAssertEqual(ChainCopyService.combine(previous: "hi", addition: ""), "hi")
    }

    func test_customSeparator() {
        XCTAssertEqual(ChainCopyService.combine(previous: "a", addition: "b", separator: "\n"), "a\nb")
    }
}
