import XCTest
@testable import ClipboardManager

final class BlobStoreTests: XCTestCase {

    private var tempRoot: URL!
    private var store: BlobStore!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blobstore-tests-\(UUID().uuidString)", isDirectory: true)
        store = try BlobStore(rootDirectory: tempRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testWriteAndReadRoundtrip() throws {
        let data = Data("png-bytes-pretend".utf8)
        let relPath = try store.write(data: data, fileExtension: "png")
        XCTAssertTrue(relPath.hasSuffix(".png"))
        XCTAssertTrue(relPath.contains("/"))  // sharded

        let loaded = try store.read(relativePath: relPath)
        XCTAssertEqual(loaded, data)
    }

    func testShardingProduces2LevelDirectoryStructure() throws {
        let data = Data("x".utf8)
        let relPath = try store.write(data: data, fileExtension: "png")
        // Expect "ab/cd/uuid.png" — 2 shards of 2 chars each.
        let parts = relPath.split(separator: "/")
        XCTAssertEqual(parts.count, 3, "expected 3 path components, got \(relPath)")
        XCTAssertEqual(parts[0].count, 2)
        XCTAssertEqual(parts[1].count, 2)
    }

    func testWritesAreUniquePerCall() throws {
        let data = Data("identical".utf8)
        let p1 = try store.write(data: data, fileExtension: "png")
        let p2 = try store.write(data: data, fileExtension: "png")
        // BlobStore doesn't dedupe — that's ClipboardStore's job.
        XCTAssertNotEqual(p1, p2)
    }

    func testDeleteRemovesFile() throws {
        let path = try store.write(data: Data([1, 2, 3]), fileExtension: "png")
        try store.delete(relativePath: path)
        XCTAssertThrowsError(try store.read(relativePath: path))
    }

    func testReadMissingFileThrows() {
        XCTAssertThrowsError(try store.read(relativePath: "ff/ee/missing.png"))
    }
}
