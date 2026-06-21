import XCTest
@testable import ClipboardManager

final class RecordingFolderTests: XCTestCase {
    func test_resolveNilBookmarkFallsBackToMovies() {
        let url = RecordingFolder.resolve(bookmark: nil)
        XCTAssertTrue(url.path.contains("Movies"))
    }

    func test_moveIntoFolderProducesTimestampedMov() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let temp = tmpDir.appendingPathComponent("source.mov")
        try Data([0x00, 0x01, 0x02]).write(to: temp)

        let dest = try RecordingFolder.moveIntoFolder(temp, folder: tmpDir, timestamp: 1718000000)
        XCTAssertTrue(dest.lastPathComponent.hasPrefix("recording-"))
        XCTAssertTrue(dest.lastPathComponent.hasSuffix(".mov"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
    }

    func test_roundTripBookmark() throws {
        let tmp = FileManager.default.temporaryDirectory
        let data = try RecordingFolder.makeBookmark(for: tmp)
        let resolved = RecordingFolder.resolve(bookmark: data)
        XCTAssertEqual(resolved.standardizedFileURL.path, tmp.standardizedFileURL.path)
    }
}
