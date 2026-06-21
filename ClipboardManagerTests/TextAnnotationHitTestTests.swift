import XCTest
import CoreGraphics
@testable import ClipboardManager

final class TextAnnotationHitTestTests: XCTestCase {

    func test_topmostIndex_pointInsideSingleRect() {
        let rects = [CGRect(x: 0, y: 0, width: 10, height: 10),
                     CGRect(x: 100, y: 100, width: 10, height: 10)]
        XCTAssertEqual(TextAnnotationHitTest.topmostIndex(rects: rects, containing: CGPoint(x: 5, y: 5)), 0)
    }

    func test_topmostIndex_overlapReturnsTopmost() {
        let rects = [CGRect(x: 0, y: 0, width: 50, height: 50),
                     CGRect(x: 10, y: 10, width: 50, height: 50)]
        XCTAssertEqual(TextAnnotationHitTest.topmostIndex(rects: rects, containing: CGPoint(x: 20, y: 20)), 1)
    }

    func test_topmostIndex_outsideReturnsNil() {
        let rects = [CGRect(x: 0, y: 0, width: 50, height: 50),
                     CGRect(x: 10, y: 10, width: 50, height: 50)]
        XCTAssertNil(TextAnnotationHitTest.topmostIndex(rects: rects, containing: CGPoint(x: 999, y: 999)))
    }

    func test_topmostIndex_ignoresNullSlots() {
        XCTAssertEqual(
            TextAnnotationHitTest.topmostIndex(
                rects: [.null, CGRect(x: 0, y: 0, width: 10, height: 10)],
                containing: CGPoint(x: 5, y: 5)),
            1)
        XCTAssertEqual(
            TextAnnotationHitTest.topmostIndex(
                rects: [CGRect(x: 0, y: 0, width: 10, height: 10), .null],
                containing: CGPoint(x: 5, y: 5)),
            0)
    }

    func test_bounds_nonEmptyAndContainsNearOrigin() {
        let r = TextAnnotationHitTest.bounds(text: "Hi", origin: CGPoint(x: 20, y: 20), fontSize: 16)
        XCTAssertGreaterThan(r.width, 0)
        XCTAssertGreaterThan(r.height, 0)
        XCTAssertTrue(r.contains(CGPoint(x: 22, y: 24)))
    }
}
