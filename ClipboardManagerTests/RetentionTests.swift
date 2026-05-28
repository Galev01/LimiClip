import XCTest
import CoreGraphics
@testable import ClipboardManager

@MainActor
final class RetentionTests: XCTestCase {

    func testRunGarbageCollectsOrphanBlobs() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        let blobRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("retention-blobs-\(UUID().uuidString)", isDirectory: true)
        let blobStore = try BlobStore(rootDirectory: blobRoot)
        defer { try? FileManager.default.removeItem(at: blobRoot) }

        // One blob referenced by a DB row; one orphan present only on disk.
        let referenced = try blobStore.write(data: Data([1, 2, 3]), fileExtension: "png")
        _ = try store.recordImage(
            contentHash: "h", blobPath: referenced,
            dimensions: CGSize(width: 1, height: 1), byteSize: 3,
            sourceApp: nil, sourceBundleId: nil
        )
        let orphan = try blobStore.write(data: Data([9, 9, 9]), fileExtension: "png")

        let defaults = UserDefaults(suiteName: "retention-gc-\(UUID().uuidString)")!
        let job = RetentionJob(store: store, blobStore: blobStore, settings: { Settings(defaults: defaults) })
        try job.runOnce()

        XCTAssertNoThrow(try blobStore.read(relativePath: referenced), "referenced blob survives GC")
        XCTAssertThrowsError(try blobStore.read(relativePath: orphan), "orphan blob is collected")
    }

    func testRunPurgesByAgeAndCount() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        try store.testingInsertStaleItem(
            body: "ancient",
            createdAt: Int64(Date().timeIntervalSince1970) - 86_400 * 200
        )
        for i in 0..<25 {
            _ = try store.recordText("item-\(i)", sourceApp: nil, sourceBundleId: nil)
        }
        // Custom settings instance with retentionDays=90 and historyLimit=10.
        let defaults = UserDefaults(suiteName: "retention-test-\(UUID().uuidString)")!
        defaults.set(90, forKey: Settings.Key.retentionDays)
        defaults.set(10, forKey: Settings.Key.historyLimit)
        let job = RetentionJob(store: store, settings: { Settings(defaults: defaults) })
        try job.runOnce()
        let remaining = try store.recentItems(limit: 100)
        XCTAssertEqual(remaining.count, 10)
        XCTAssertFalse(remaining.map(\.body).contains("ancient"))
    }
}
