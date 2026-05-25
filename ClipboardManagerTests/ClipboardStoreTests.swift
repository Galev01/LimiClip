import XCTest
import GRDB
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
}
