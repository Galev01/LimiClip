import XCTest
import GRDB
import CoreGraphics
@testable import ClipboardManager

final class ClipboardStoreTests: XCTestCase {

    private func makeStore() throws -> ClipboardStore {
        // In-memory DB, fresh per test. Use a constant key — not Keychain.
        let cfg = ClipboardStore.testingConfiguration()
        return try ClipboardStore(configuration: cfg)
    }

    func testInsertCreatesRow() throws {
        let store = try makeStore()
        let inserted = try store.recordText(
            "hello world",
            sourceApp: "TestApp",
            sourceBundleId: "test.app"
        )
        XCTAssertNotNil(inserted)
        XCTAssertEqual(try store.countItems(), 1)
    }

    func testInsertDedupesByContentHash() throws {
        let store = try makeStore()
        let first = try store.recordText("same", sourceApp: nil, sourceBundleId: nil)
        // Re-insert identical content.
        let second = try store.recordText("same", sourceApp: nil, sourceBundleId: nil)
        XCTAssertEqual(try store.countItems(), 1)
        XCTAssertEqual(first?.id, second?.id)
        // createdAt should have advanced.
        XCTAssertGreaterThanOrEqual(second?.createdAt ?? 0, first?.createdAt ?? 0)
    }

    func testRecentItemsAreOrderedNewestFirst() throws {
        let store = try makeStore()
        _ = try store.recordText("oldest", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("middle", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("newest", sourceApp: nil, sourceBundleId: nil)
        let recent = try store.recentItems(limit: 10)
        XCTAssertEqual(recent.map(\.body), ["newest", "middle", "oldest"])
    }

    func testEmptyAndWhitespaceItemsRejected() throws {
        let store = try makeStore()
        XCTAssertNil(try store.recordText("", sourceApp: nil, sourceBundleId: nil))
        XCTAssertNil(try store.recordText("    \n   ", sourceApp: nil, sourceBundleId: nil))
        XCTAssertEqual(try store.countItems(), 0)
    }

    func testSeedDefaultExclusionsRunsOnce() throws {
        let store = try makeStore()
        try store.seedDefaultExclusionsIfNeeded()
        let firstCount = try store.allExclusions().count
        XCTAssertGreaterThan(firstCount, 0)
        // Idempotent.
        try store.seedDefaultExclusionsIfNeeded()
        let secondCount = try store.allExclusions().count
        XCTAssertEqual(firstCount, secondCount)
    }

    func testExcludedBundleIdSkipped() throws {
        let store = try makeStore()
        try store.addExclusion(bundleId: "com.bad.app", name: "Bad App")
        let result = try store.recordText("secret", sourceApp: "Bad App", sourceBundleId: "com.bad.app")
        XCTAssertNil(result)
        XCTAssertEqual(try store.countItems(), 0)
    }

    func testSoftDelete() throws {
        let store = try makeStore()
        let inserted = try store.recordText("temporary", sourceApp: nil, sourceBundleId: nil)
        try store.softDelete(itemId: inserted!.id!)
        XCTAssertEqual(try store.recentItems(limit: 10).count, 0)
        XCTAssertEqual(try store.countItems(includingDeleted: true), 1)
    }

    func testPurgeRemovesItemsOlderThanRetentionWindow() throws {
        let store = try makeStore()
        // Force-insert with a stale timestamp.
        let stale = Int64(Date().timeIntervalSince1970) - 60 * 60 * 24 * 200  // 200 days ago
        try store.testingInsertStaleItem(body: "old", createdAt: stale)
        _ = try store.recordText("fresh", sourceApp: nil, sourceBundleId: nil)

        try store.purgeOlderThan(days: 90)
        let recent = try store.recentItems(limit: 100)
        XCTAssertEqual(recent.map(\.body), ["fresh"])
    }

    func testPurgeRemovesItemsBeyondMaxCount() throws {
        let store = try makeStore()
        for i in 0..<20 {
            _ = try store.recordText("item-\(i)", sourceApp: nil, sourceBundleId: nil)
        }
        try store.purgeBeyondCount(max: 10)
        XCTAssertEqual(try store.recentItems(limit: 100).count, 10)
        // Newest 10 retained.
        let bodies = try store.recentItems(limit: 100).map(\.body)
        XCTAssertEqual(bodies.first, "item-19")
        XCTAssertEqual(bodies.last, "item-10")
    }

    // MARK: - Phase 3: image + file

    func testRecordImageStoresWithBlobPathAndDimensions() throws {
        let store = try makeStore()
        // imageHash is independent of body; we pass the raw bytes' hash explicitly.
        let imageBytes = Data([0xff, 0xee, 0xdd, 0xcc])
        let inserted = try store.recordImage(
            contentHash: "abc123",
            blobPath: "ab/cd/uuid.png",
            dimensions: CGSize(width: 4032, height: 3024),
            byteSize: imageBytes.count,
            sourceApp: "Screenshot",
            sourceBundleId: nil
        )
        XCTAssertNotNil(inserted)
        XCTAssertEqual(inserted?.kind, "image")
        XCTAssertEqual(inserted?.blobPath, "ab/cd/uuid.png")
        XCTAssertEqual(inserted?.dimensions, "4032x3024")
        XCTAssertEqual(inserted?.body, "ab/cd/uuid.png")
    }

    func testRecordImageDedupesByContentHash() throws {
        let store = try makeStore()
        let a = try store.recordImage(
            contentHash: "samehash",
            blobPath: "aa/bb/first.png", dimensions: CGSize(width: 100, height: 100),
            byteSize: 10, sourceApp: nil, sourceBundleId: nil
        )
        let b = try store.recordImage(
            contentHash: "samehash",
            blobPath: "cc/dd/second.png", dimensions: CGSize(width: 100, height: 100),
            byteSize: 10, sourceApp: nil, sourceBundleId: nil
        )
        XCTAssertEqual(a?.id, b?.id)
        XCTAssertEqual(try store.countItems(), 1)
    }

    func testRecordFileStoresJSONReference() throws {
        let store = try makeStore()
        let ref = FileReference(
            path: "/Users/gal/Documents/spec.pdf",
            name: "spec.pdf",
            byteSize: 1024,
            modifiedAt: 1_700_000_000
        )
        let inserted = try store.recordFile(reference: ref, sourceApp: "Finder", sourceBundleId: "com.apple.finder")
        XCTAssertNotNil(inserted)
        XCTAssertEqual(inserted?.kind, "file")
        let decoded = try FileReference.decodingJSON(inserted!.body)
        XCTAssertEqual(decoded, ref)
    }

    func testRecordFileDedupesByPath() throws {
        let store = try makeStore()
        let ref = FileReference(path: "/x/y/a.pdf", name: "a.pdf", byteSize: 1, modifiedAt: 1)
        let first = try store.recordFile(reference: ref, sourceApp: nil, sourceBundleId: nil)
        let second = try store.recordFile(reference: ref, sourceApp: nil, sourceBundleId: nil)
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(try store.countItems(), 1)
    }

    func testSetPinnedPinsAnItem() throws {
        let store = try makeStore()
        let inserted = try store.recordText("pin me", sourceApp: nil, sourceBundleId: nil)
        let id = try XCTUnwrap(inserted?.id)

        try store.setPinned(itemId: id, pinned: true)

        let items = try store.recentItems(limit: 10)
        let found = try XCTUnwrap(items.first { $0.id == id })
        XCTAssertTrue(found.pinned)
    }

    func testSetPinnedUnpinsAnItem() throws {
        let store = try makeStore()
        let inserted = try store.recordText("unpin me", sourceApp: nil, sourceBundleId: nil)
        let id = try XCTUnwrap(inserted?.id)

        try store.setPinned(itemId: id, pinned: true)
        try store.setPinned(itemId: id, pinned: false)

        let items = try store.recentItems(limit: 10)
        let found = try XCTUnwrap(items.first { $0.id == id })
        XCTAssertFalse(found.pinned)
    }

    func testPinnedItemSurvivesPurge() throws {
        let store = try makeStore()
        // Insert a stale item that would normally be purged.
        let stale = Int64(Date().timeIntervalSince1970) - 60 * 60 * 24 * 200  // 200 days ago
        try store.testingInsertStaleItem(body: "pinned survivor", createdAt: stale)

        let all = try store.recentItems(limit: 10)
        let staleItem = try XCTUnwrap(all.first { $0.body == "pinned survivor" })
        let id = try XCTUnwrap(staleItem.id)

        try store.setPinned(itemId: id, pinned: true)
        try store.purgeOlderThan(days: 0)  // purge everything older than now

        let surviving = try store.recentItems(limit: 10)
        XCTAssertTrue(surviving.contains { $0.id == id }, "pinned item should survive purge")
    }

    func testClearAllDeletesNonPinnedItems() throws {
        let store = try makeStore()
        let a = try store.recordText("item-a", sourceApp: nil, sourceBundleId: nil)
        let b = try store.recordText("item-b", sourceApp: nil, sourceBundleId: nil)
        let c = try store.recordText("pinned-item", sourceApp: nil, sourceBundleId: nil)
        let cId = try XCTUnwrap(c?.id)
        try store.setPinned(itemId: cId, pinned: true)
        let softDeletedItem = try store.recordText("soft-deleted", sourceApp: nil, sourceBundleId: nil)
        let softId = try XCTUnwrap(softDeletedItem?.id)
        try store.softDelete(itemId: softId)

        try store.clearAll()

        // Non-pinned active items are gone.
        let remaining = try store.recentItems(limit: 10)
        XCTAssertEqual(remaining.count, 1, "only the pinned item should remain")
        XCTAssertEqual(remaining.first?.body, "pinned-item")
        XCTAssertNil(remaining.first { $0.id == a?.id })
        XCTAssertNil(remaining.first { $0.id == b?.id })
        // Soft-deleted item (deletedAt IS NOT NULL) must survive clearAll.
        XCTAssertEqual(try store.countItems(includingDeleted: true), 2) // pinned + soft-deleted
    }

    func testClearAllOnEmptyStoreSucceeds() throws {
        let store = try makeStore()
        XCTAssertNoThrow(try store.clearAll())
        XCTAssertEqual(try store.countItems(), 0)
    }
}
