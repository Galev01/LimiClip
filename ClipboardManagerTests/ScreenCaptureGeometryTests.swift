import XCTest
import CoreGraphics
@testable import ClipboardManager

final class ScreenCaptureGeometryTests: XCTestCase {

    func test_pixelRectScalesByBackingFactor() {
        let r = ScreenCaptureGeometry.pixelRect(
            viewRect: CGRect(x: 10, y: 20, width: 100, height: 50), scale: 2)
        XCTAssertEqual(r, CGRect(x: 20, y: 40, width: 200, height: 100))
    }

    func test_pixelRectIdentityAtScaleOne() {
        let v = CGRect(x: 5, y: 6, width: 7, height: 8)
        XCTAssertEqual(ScreenCaptureGeometry.pixelRect(viewRect: v, scale: 1), v)
    }

    func test_toSelectionPixelsShiftsAndScales() {
        let p = ScreenCaptureGeometry.toSelectionPixels(
            CGPoint(x: 60, y: 80), selectionOrigin: CGPoint(x: 10, y: 20), scale: 2)
        XCTAssertEqual(p, CGPoint(x: 100, y: 120))
    }
}
