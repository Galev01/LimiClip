// ClipboardManagerTests/CompactPopupGeometryTests.swift
import XCTest
@testable import ClipboardManager

final class CompactPopupGeometryTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testWidthIsAlwaysPopupWidth() {
        let f = CompactPopupGeometry.frame(near: NSPoint(x: 720, y: 400), itemCount: 5, in: screen)
        XCTAssertEqual(f.width, CompactPopupGeometry.popupWidth)
    }

    func testPopupAppearsAboveCursor() {
        let cursor = NSPoint(x: 720, y: 400)
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 3, in: screen)
        // Bottom edge of popup is at or above cursor
        XCTAssertGreaterThanOrEqual(f.minY, cursor.y)
    }

    func testCenteredHorizontallyOnCursor() {
        let cursor = NSPoint(x: 720, y: 400)
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 3, in: screen)
        let expectedX = cursor.x - CompactPopupGeometry.popupWidth / 2
        XCTAssertEqual(f.minX, expectedX, accuracy: 0.5)
    }

    func testClampedToLeftEdge() {
        let cursor = NSPoint(x: 5, y: 400) // near left edge
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 1, in: screen)
        XCTAssertGreaterThanOrEqual(f.minX, screen.minX + CompactPopupGeometry.edgeInset - 0.5)
    }

    func testClampedToRightEdge() {
        let cursor = NSPoint(x: 1435, y: 400) // near right edge
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 1, in: screen)
        XCTAssertLessThanOrEqual(f.maxX, screen.maxX - CompactPopupGeometry.edgeInset + 0.5)
    }

    func testClampedToTopEdge() {
        let cursor = NSPoint(x: 720, y: 890) // near top
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 10, in: screen)
        XCTAssertLessThanOrEqual(f.maxY, screen.maxY - CompactPopupGeometry.edgeInset + 0.5)
    }

    func testHeightCappedAtMaxHeight() {
        let f = CompactPopupGeometry.frame(near: NSPoint(x: 720, y: 400), itemCount: 10, in: screen)
        XCTAssertLessThanOrEqual(f.height, CompactPopupGeometry.maxHeight)
    }

    func testZeroItemsProducesMinimumHeight() {
        let f = CompactPopupGeometry.frame(near: NSPoint(x: 720, y: 400), itemCount: 0, in: screen)
        XCTAssertGreaterThan(f.height, 0)
    }

    func testOffsetScreenUsesScreenOrigin() {
        // Screen at non-zero origin (e.g. second monitor)
        let offset = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let cursor = NSPoint(x: 1442, y: 500) // near left edge of this screen
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 1, in: offset)
        XCTAssertGreaterThanOrEqual(f.minX, offset.minX + CompactPopupGeometry.edgeInset - 0.5)
    }
}
