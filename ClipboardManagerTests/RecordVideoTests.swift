import XCTest
import GRDB
@testable import ClipboardManager

final class RecordVideoTests: XCTestCase {

    private func makeBlobStore() throws -> (BlobStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("recvideo-\(UUID().uuidString)", isDirectory: true)
        return (try BlobStore(rootDirectory: root), root)
    }

    func test_recordsVideoRow() throws {
        let (blobStore, root) = try makeBlobStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration(), blobStore: blobStore)

        let thumbPath = try blobStore.write(data: Data([1, 2, 3, 4]), fileExtension: "png")
        let ref = VideoReference(
            path: "/Users/gal/Movies/recording-1700000000.mov",
            name: "recording-1700000000.mov",
            byteSize: 9_999_999,
            modifiedAt: 1_700_000_000,
            durationSeconds: 12.5,
            width: 1920,
            height: 1080
        )

        let inserted = try store.recordVideo(reference: ref, thumbnailBlobPath: thumbPath, sourceApp: "Screen Recording")
        XCTAssertNotNil(inserted)
        XCTAssertEqual(inserted?.kind, "video")
        XCTAssertEqual(inserted?.dimensions, "1920x1080")
        XCTAssertEqual(inserted?.blobPath, thumbPath)

        let recent = try store.recentItems(limit: 10)
        XCTAssertTrue(recent.contains { $0.id == inserted?.id })

        let decoded = try VideoReference.decodingJSON(inserted!.body)
        XCTAssertEqual(decoded, ref)
    }

    func test_softDeleteKeepsExternalMovFile() throws {
        let (blobStore, root) = try makeBlobStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration(), blobStore: blobStore)

        // A real .mov file on disk that the video item references.
        let movURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("recording-\(UUID().uuidString).mov", isDirectory: false)
        try Data([0xAA, 0xBB, 0xCC]).write(to: movURL)
        defer { try? FileManager.default.removeItem(at: movURL) }

        let thumbPath = try blobStore.write(data: Data([9, 9, 9]), fileExtension: "png")
        let ref = VideoReference(
            path: movURL.path,
            name: movURL.lastPathComponent,
            byteSize: 3,
            modifiedAt: 1_700_000_000,
            durationSeconds: 1.0,
            width: 100,
            height: 100
        )
        let inserted = try store.recordVideo(reference: ref, thumbnailBlobPath: thumbPath, sourceApp: nil)
        let id = try XCTUnwrap(inserted?.id)

        try store.softDelete(itemId: id)

        // The thumbnail blob is GC'd (like image blobs)…
        XCTAssertThrowsError(try blobStore.read(relativePath: thumbPath), "thumbnail blob should be eagerly deleted")
        // …but the user's .mov on disk must be untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: movURL.path), "soft-delete must NOT delete the external .mov file")
    }

    func test_recordVideoDedupesByPath() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        let ref = VideoReference(
            path: "/Users/gal/Movies/dup.mov", name: "dup.mov", byteSize: 1, modifiedAt: 1,
            durationSeconds: 1, width: 10, height: 10
        )
        let first = try store.recordVideo(reference: ref, thumbnailBlobPath: nil, sourceApp: nil)
        let second = try store.recordVideo(reference: ref, thumbnailBlobPath: nil, sourceApp: nil)
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(try store.countItems(), 1)
    }
}
