import XCTest
import AppKit
@testable import ClipboardManager

final class ImageAnnotatorTests: XCTestCase {
    private func solidImage(_ size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        img.unlockFocus()
        return img
    }

    func test_flattenReturnsPNGOfSamePixelSize() throws {
        let base = solidImage(NSSize(width: 100, height: 80))
        let ann = Annotation(id: UUID(), tool: .rectangle,
                             points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 50)],
                             text: "", colorHex: "#FF0000", lineWidth: 4)
        let data = try ImageAnnotator.flatten(base: base, annotations: [ann])
        let out = try XCTUnwrap(NSImage(data: data))
        let rep = try XCTUnwrap(out.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep.pixelsWide, 100)
        XCTAssertEqual(rep.pixelsHigh, 80)
        XCTAssertFalse(data.isEmpty)
    }

    func test_flattenWithAnnotationDiffersFromBlank() throws {
        let base = solidImage(NSSize(width: 50, height: 50))
        let blank = try ImageAnnotator.flatten(base: base, annotations: [])
        let pen = Annotation(id: UUID(), tool: .pen,
                             points: [CGPoint(x: 5, y: 5), CGPoint(x: 45, y: 45)],
                             text: "", colorHex: "#000000", lineWidth: 6)
        let drawn = try ImageAnnotator.flatten(base: base, annotations: [pen])
        XCTAssertNotEqual(blank, drawn)
    }
}
