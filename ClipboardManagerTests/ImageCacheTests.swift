import XCTest
import AppKit
@testable import ClipboardManager

final class ImageCacheTests: XCTestCase {

    private var tempRoot: URL!
    private var blobStore: BlobStore!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("imgcache-tests-\(UUID().uuidString)", isDirectory: true)
        let cipher = FieldCipher(masterKeyData: Data(repeating: 5, count: 32))
        blobStore = try BlobStore(rootDirectory: tempRoot, cipher: cipher)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// Encodes a tiny valid PNG and writes it (encrypted) to the blob store,
    /// returning its relative path.
    private func writePNGBlob() throws -> String {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        return try blobStore.write(data: png, fileExtension: "png")
    }

    func testDecodesEncryptedBlobIntoImage() throws {
        let cache = ImageCache()
        let path = try writePNGBlob()
        XCTAssertNotNil(cache.image(forKey: path, blobStore: blobStore, path: path))
    }

    func testSameKeyReturnsCachedInstanceWithoutRereading() throws {
        let cache = ImageCache()
        let path = try writePNGBlob()
        let first = try XCTUnwrap(cache.image(forKey: path, blobStore: blobStore, path: path))
        // Delete the backing file: a genuine cache hit must not need to re-read it.
        try blobStore.delete(relativePath: path)
        let second = cache.image(forKey: path, blobStore: blobStore, path: path)
        XCTAssertTrue(first === second, "same key must return the cached instance, not re-decode")
    }

    func testDistinctKeysGetDistinctImages() throws {
        let cache = ImageCache()
        let a = try writePNGBlob()
        let b = try writePNGBlob()
        let ia = try XCTUnwrap(cache.image(forKey: a, blobStore: blobStore, path: a))
        let ib = try XCTUnwrap(cache.image(forKey: b, blobStore: blobStore, path: b))
        XCTAssertFalse(ia === ib, "different keys must not collide")
    }

    func testMissingBlobReturnsNil() {
        let cache = ImageCache()
        XCTAssertNil(cache.image(forKey: "missing", blobStore: blobStore, path: "ff/ee/missing.png"))
    }

    func testCacheReturnsSameInstanceOnHit() throws {
        let blobs = try BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("imgcache-\(UUID().uuidString)", isDirectory: true))
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        let path = try blobs.write(data: png, fileExtension: "png")
        let cache = ImageCache()
        let a = cache.image(forKey: "k", blobStore: blobs, path: path)
        let b = cache.image(forKey: "k", blobStore: blobs, path: path)
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b, "second call must be a cache hit (same instance)")
    }
}
