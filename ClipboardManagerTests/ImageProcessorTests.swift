import XCTest
import AppKit
@testable import ClipboardManager

final class ImageProcessorTests: XCTestCase {

    private func makeImageData(width: Int, height: Int) -> Data {
        // Build the bitmap directly with explicit pixel dimensions so the
        // result is always exactly width×height pixels regardless of display
        // scale factor (avoids NSImage Retina 2x inflation).
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func testProcessSmallImagePassesThroughDimensions() throws {
        let png = makeImageData(width: 200, height: 100)
        let result = try ImageProcessor.process(data: png)
        XCTAssertEqual(result.pixelSize.width, 200)
        XCTAssertEqual(result.pixelSize.height, 100)
        XCTAssertGreaterThan(result.thumbnailData.count, 0)
        // Thumbnail PNG is still valid.
        XCTAssertNotNil(NSImage(data: result.thumbnailData))
    }

    func testProcessDownsamplesLargeImage() throws {
        let png = makeImageData(width: 4000, height: 3000)
        let result = try ImageProcessor.process(data: png)
        // Original dimensions are preserved on the result.
        XCTAssertEqual(result.pixelSize.width, 4000)
        XCTAssertEqual(result.pixelSize.height, 3000)
        // But the thumbnail PNG's max side must be ≤ 800.
        let thumb = NSImage(data: result.thumbnailData)!
        let rep = thumb.representations.first as? NSBitmapImageRep ?? NSBitmapImageRep(data: result.thumbnailData)!
        XCTAssertLessThanOrEqual(max(rep.pixelsWide, rep.pixelsHigh), 800)
    }

    func testInvalidDataThrows() {
        let bogus = Data("not an image".utf8)
        XCTAssertThrowsError(try ImageProcessor.process(data: bogus))
    }
}
