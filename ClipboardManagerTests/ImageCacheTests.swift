import XCTest
import AppKit
@testable import ClipboardManager

final class ImageCacheTests: XCTestCase {

    /// Writes a tiny valid PNG to a temp file and returns its URL.
    private func writePNG() throws -> URL {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("imgcache-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    func testDecodesAndReturnsImage() throws {
        let cache = ImageCache()
        let url = try writePNG()
        XCTAssertNotNil(cache.image(forKey: "a", url: url))
    }

    func testSameKeyReturnsCachedInstanceWithoutRereading() throws {
        let cache = ImageCache()
        let url = try writePNG()
        let first = try XCTUnwrap(cache.image(forKey: "k", url: url))
        // Remove the backing file: a genuine cache hit must not need to re-read it.
        try FileManager.default.removeItem(at: url)
        let second = cache.image(forKey: "k", url: url)
        XCTAssertTrue(first === second, "same key must return the cached instance, not re-decode")
    }

    func testDistinctKeysGetDistinctImages() throws {
        let cache = ImageCache()
        let a = try writePNG()
        let b = try writePNG()
        let ia = try XCTUnwrap(cache.image(forKey: "a", url: a))
        let ib = try XCTUnwrap(cache.image(forKey: "b", url: b))
        XCTAssertFalse(ia === ib, "different keys must not collide")
    }

    func testMissingFileReturnsNil() {
        let cache = ImageCache()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).png")
        XCTAssertNil(cache.image(forKey: "missing", url: url))
    }
}
