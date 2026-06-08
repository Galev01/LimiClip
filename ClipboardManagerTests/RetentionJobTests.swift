import XCTest
@testable import ClipboardManager

@MainActor
final class RetentionJobTests: XCTestCase {
    func testDoubleStartDoesNotStackTimers() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        let job = RetentionJob(store: store)
        job.start()
        job.start()   // second start must be a no-op
        XCTAssertTrue(job.hasActiveTimer, "timer should be active")
        job.stop()
        XCTAssertFalse(job.hasActiveTimer, "timer should be cleared after stop")
    }
}
