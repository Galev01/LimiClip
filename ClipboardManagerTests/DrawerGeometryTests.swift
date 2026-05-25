import XCTest
@testable import ClipboardManager

final class DrawerGeometryTests: XCTestCase {

    func testOnScreenFrameSpansScreenAndSitsAtBottom() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let f = DrawerGeometry.onScreenFrame(in: screen, height: 300)
        XCTAssertEqual(f.origin.x, 0)
        XCTAssertEqual(f.origin.y, 0)
        XCTAssertEqual(f.size.width, 1440)
        XCTAssertEqual(f.size.height, 300)
    }

    func testOffScreenFrameIsBelowScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let f = DrawerGeometry.offScreenFrame(in: screen, height: 300)
        XCTAssertEqual(f.origin.x, 0)
        XCTAssertEqual(f.origin.y, -300)
        XCTAssertEqual(f.size.width, 1440)
        XCTAssertEqual(f.size.height, 300)
    }

    func testFramesUseProvidedHeight() {
        let screen = CGRect(x: 100, y: 200, width: 1000, height: 800)
        let on = DrawerGeometry.onScreenFrame(in: screen, height: 250)
        XCTAssertEqual(on.origin, CGPoint(x: 100, y: 200))
        XCTAssertEqual(on.size, CGSize(width: 1000, height: 250))
    }
}
