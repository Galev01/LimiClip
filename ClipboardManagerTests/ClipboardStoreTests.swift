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

    // MARK: - Caps: photos (drop oldest beyond 5) and pins (evict oldest beyond 15)

    func testRecordImageEvictsOldestPhotoBeyondLimit() throws {
        let store = try makeStore()
        // Record 6 distinct non-pinned photos; the cap is 5.
        for i in 0..<6 {
            _ = try store.recordImage(
                contentHash: "hash-\(i)",
                blobPath: "aa/bb/img-\(i).png",
                dimensions: CGSize(width: 10, height: 10),
                byteSize: 10, sourceApp: nil, sourceBundleId: nil
            )
        }
        let images = try store.recentItems(limit: 100).filter { $0.kind == "image" }
        XCTAssertEqual(images.count, 5, "non-pinned photos are capped at 5")
        let paths = Set(images.compactMap(\.blobPath))
        XCTAssertFalse(paths.contains("aa/bb/img-0.png"), "oldest photo should be evicted")
        XCTAssertTrue(paths.contains("aa/bb/img-5.png"), "newest photo should be retained")
    }

    func testPinnedPhotosDoNotCountTowardImageCap() throws {
        let store = try makeStore()
        // Three pinned photos.
        var pinnedIds: [Int64] = []
        for i in 0..<3 {
            let img = try store.recordImage(
                contentHash: "p-\(i)", blobPath: "aa/bb/p-\(i).png",
                dimensions: CGSize(width: 10, height: 10),
                byteSize: 10, sourceApp: nil, sourceBundleId: nil
            )
            pinnedIds.append(try XCTUnwrap(img?.id))
        }
        for id in pinnedIds { try store.setPinned(itemId: id, pinned: true) }
        // Six non-pinned photos on top.
        for i in 0..<6 {
            _ = try store.recordImage(
                contentHash: "n-\(i)", blobPath: "aa/bb/n-\(i).png",
                dimensions: CGSize(width: 10, height: 10),
                byteSize: 10, sourceApp: nil, sourceBundleId: nil
            )
        }
        let images = try store.recentItems(limit: 100).filter { $0.kind == "image" }
        XCTAssertEqual(images.filter { $0.pinned }.count, 3, "pinned photos are not evicted by the cap")
        XCTAssertEqual(images.filter { !$0.pinned }.count, 5, "non-pinned photos are capped at 5")
    }

    func testReferencedBlobPathsDropsBlobOfEagerlyDeletedImage() throws {
        let store = try makeStore()
        _ = try store.recordImage(
            contentHash: "h1", blobPath: "aa/bb/one.png",
            dimensions: CGSize(width: 1, height: 1), byteSize: 1,
            sourceApp: nil, sourceBundleId: nil
        )
        let two = try store.recordImage(
            contentHash: "h2", blobPath: "cc/dd/two.png",
            dimensions: CGSize(width: 1, height: 1), byteSize: 1,
            sourceApp: nil, sourceBundleId: nil
        )
        _ = try store.recordText("text only", sourceApp: nil, sourceBundleId: nil)
        // Deleting an item now eagerly drops its blob (no 24h grace / no undo),
        // so its path is nulled and GC no longer counts it as referenced.
        try store.softDelete(itemId: try XCTUnwrap(two?.id))

        XCTAssertEqual(try store.referencedBlobPaths(), ["aa/bb/one.png"])
    }

    func testSetPinnedEvictsOldestPinBeyondLimit() throws {
        let store = try makeStore()
        var ids: [Int64] = []
        for i in 0..<16 {
            let it = try store.recordText("item-\(i)", sourceApp: nil, sourceBundleId: nil)
            ids.append(try XCTUnwrap(it?.id))
        }
        // Pin all 16 in insertion order; the cap is 15.
        for id in ids { try store.setPinned(itemId: id, pinned: true) }

        let all = try store.recentItems(limit: 100)
        XCTAssertEqual(all.filter { $0.pinned }.count, 15, "pinned items are capped at 15")
        // The oldest pin is evicted (unpinned) but the row survives.
        let oldest = try XCTUnwrap(all.first { $0.id == ids[0] })
        XCTAssertFalse(oldest.pinned, "oldest pin should be unpinned, not deleted")
        XCTAssertEqual(all.count, 16, "evicting a pin must not delete the row")
    }

    // MARK: - Captured text size cap

    func testRejectsTextLargerThanCap() throws {
        let store = try makeStore()
        let oversized = String(repeating: "a", count: ClipboardStore.maxTextBytes + 1)
        let result = try store.recordText(oversized, sourceApp: nil, sourceBundleId: nil)
        XCTAssertNil(result)
        XCTAssertEqual(try store.countItems(), 0)
    }

    func testAcceptsTextAtExactlyTheCap() throws {
        let store = try makeStore()
        let atCap = String(repeating: "a", count: ClipboardStore.maxTextBytes)
        let result = try store.recordText(atCap, sourceApp: nil, sourceBundleId: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(try store.countItems(), 1)
        XCTAssertEqual(result?.byteSize, ClipboardStore.maxTextBytes)
    }

    func testCapIsMeasuredInUTF8BytesNotCharacters() throws {
        let store = try makeStore()
        // "\u{1F510}" is 4 UTF-8 bytes but 1 Character; pick a count so the
        // character count stays under the cap while the byte count exceeds it.
        let charCount = (ClipboardStore.maxTextBytes / 4) + 1
        let emoji = String(repeating: "\u{1F510}", count: charCount)
        XCTAssertLessThanOrEqual(emoji.count, ClipboardStore.maxTextBytes)
        XCTAssertGreaterThan(emoji.utf8.count, ClipboardStore.maxTextBytes)
        XCTAssertNil(try store.recordText(emoji, sourceApp: nil, sourceBundleId: nil))
        XCTAssertEqual(try store.countItems(), 0)
    }

    func testNormalSizedTextStillCaptured() throws {
        let store = try makeStore()
        let result = try store.recordText("a perfectly normal clipboard string", sourceApp: nil, sourceBundleId: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(try store.recentItems(limit: 5).map(\.body), ["a perfectly normal clipboard string"])
    }

    func testRecordImageRejectsOversizeBytes() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        let huge = ClipboardStore.maxImageBytes + 1
        let item = try store.recordImage(
            contentHash: "oversize",
            blobPath: "aa/bb/x.png",
            dimensions: CGSize(width: 1, height: 1),
            byteSize: huge,
            sourceApp: nil,
            sourceBundleId: nil
        )
        XCTAssertNil(item, "oversize image must be dropped")
    }

    // MARK: - Eager blob delete on single-item delete

    private func makeBlobStore() throws -> (BlobStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eager-\(UUID().uuidString)", isDirectory: true)
        return (try BlobStore(rootDirectory: root), root)
    }

    func testSoftDeleteEagerlyDeletesImageBlob() throws {
        let (blobStore, root) = try makeBlobStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration(), blobStore: blobStore)

        let path = try blobStore.write(data: Data([1, 2, 3]), fileExtension: "png")
        let img = try store.recordImage(contentHash: "h1", blobPath: path,
            dimensions: CGSize(width: 1, height: 1), byteSize: 3, sourceApp: nil, sourceBundleId: nil)
        let id = try XCTUnwrap(img?.id)
        XCTAssertNoThrow(try blobStore.read(relativePath: path), "precondition: blob exists")

        try store.softDelete(itemId: id)

        XCTAssertThrowsError(try blobStore.read(relativePath: path), "blob must be deleted eagerly on single-item delete")
        XCTAssertEqual(try store.countItems(includingDeleted: true), 1)
        XCTAssertFalse(try store.referencedBlobPaths().contains(path))
    }

    func testSoftDeleteKeepsBlobIfAnotherLiveRowReferencesIt() throws {
        let (blobStore, root) = try makeBlobStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration(), blobStore: blobStore)

        let shared = try blobStore.write(data: Data([7, 7, 7]), fileExtension: "png")
        let a = try store.recordImage(contentHash: "ha", blobPath: shared,
            dimensions: CGSize(width: 1, height: 1), byteSize: 3, sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordImage(contentHash: "hb", blobPath: shared,
            dimensions: CGSize(width: 1, height: 1), byteSize: 3, sourceApp: nil, sourceBundleId: nil)
        let aId = try XCTUnwrap(a?.id)

        try store.softDelete(itemId: aId)

        XCTAssertNoThrow(try blobStore.read(relativePath: shared), "shared blob must survive while another live row references it")
        XCTAssertTrue(try store.referencedBlobPaths().contains(shared))
    }

    func testSoftDeleteTextItemIgnoresBlobStore() throws {
        let (blobStore, root) = try makeBlobStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration(), blobStore: blobStore)

        let txt = try store.recordText("secret note", sourceApp: nil, sourceBundleId: nil)
        let id = try XCTUnwrap(txt?.id)

        XCTAssertNoThrow(try store.softDelete(itemId: id))
        XCTAssertEqual(try store.recentItems(limit: 10).count, 0)
        XCTAssertEqual(try store.countItems(includingDeleted: true), 1)
    }

    func testSoftDeleteWithoutBlobStoreStillSoftDeletes() throws {
        let store = try makeStore()  // no blobStore injected
        let img = try store.recordImage(contentHash: "h", blobPath: "aa/bb/x.png",
            dimensions: CGSize(width: 1, height: 1), byteSize: 1, sourceApp: nil, sourceBundleId: nil)
        let id = try XCTUnwrap(img?.id)
        XCTAssertNoThrow(try store.softDelete(itemId: id))
        XCTAssertEqual(try store.recentItems(limit: 10).count, 0)
        XCTAssertEqual(try store.countItems(includingDeleted: true), 1)
    }

    func testSoftDeleteMissingBlobDoesNotThrow() throws {
        let (blobStore, root) = try makeBlobStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration(), blobStore: blobStore)

        let img = try store.recordImage(contentHash: "h", blobPath: "ff/ee/never.png",
            dimensions: CGSize(width: 1, height: 1), byteSize: 1, sourceApp: nil, sourceBundleId: nil)
        let id = try XCTUnwrap(img?.id)
        XCTAssertNoThrow(try store.softDelete(itemId: id), "missing blob must not surface as an error")
        XCTAssertEqual(try store.countItems(includingDeleted: true), 1)
    }
}
