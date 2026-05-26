import XCTest
@testable import ClipboardManager

@MainActor
final class RetentionTests: XCTestCase {

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
