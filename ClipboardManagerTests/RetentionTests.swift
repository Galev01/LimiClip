import XCTest
@testable import ClipboardManager

@MainActor
final class RetentionTests: XCTestCase {

    func testRunPurgesByAgeAndCount() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        // 200-day-old item.
        try store.testingInsertStaleItem(
            body: "ancient",
            createdAt: Int64(Date().timeIntervalSince1970) - 86_400 * 200
        )
        for i in 0..<25 {
            _ = try store.recordText("item-\(i)", sourceApp: nil, sourceBundleId: nil)
        }
        let job = RetentionJob(store: store, retentionDays: 90, maxItems: 10)
        try job.runOnce()
        let remaining = try store.recentItems(limit: 100)
        XCTAssertEqual(remaining.count, 10)
        XCTAssertFalse(remaining.map(\.body).contains("ancient"))
    }
}
