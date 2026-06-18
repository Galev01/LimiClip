import XCTest
@testable import ClipboardManager

final class AnnotationFolderTests: XCTestCase {
    func test_resolveNilBookmarkFallsBackToPictures() {
        let url = AnnotationFolder.resolve(bookmark: nil)
        XCTAssertTrue(url.path.contains("Pictures"))
    }

    func test_writeProducesTimestampedPNG() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let out = try AnnotationFolder.write(png: Data([0x89, 0x50]), to: tmp, timestamp: 1718000000)
        XCTAssertTrue(out.lastPathComponent.hasPrefix("annotated-"))
        XCTAssertTrue(out.lastPathComponent.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    }

    func test_roundTripBookmark() throws {
        let tmp = FileManager.default.temporaryDirectory
        let data = try AnnotationFolder.makeBookmark(for: tmp)
        let resolved = AnnotationFolder.resolve(bookmark: data)
        XCTAssertEqual(resolved.standardizedFileURL.path, tmp.standardizedFileURL.path)
    }
}
