import XCTest
@testable import ClipboardManager

final class DatabaseKeyDecisionTests: XCTestCase {

    func test_keyPresentAlwaysUsesExisting() {
        XCTAssertEqual(DatabaseKey.decide(keyPresent: true, previouslyProvisioned: false), .useExisting)
        XCTAssertEqual(DatabaseKey.decide(keyPresent: true, previouslyProvisioned: true), .useExisting)
    }

    func test_freshInstallCreatesFirstKey() {
        // No key, never provisioned → legitimate first run.
        XCTAssertEqual(DatabaseKey.decide(keyPresent: false, previouslyProvisioned: false), .createFirst)
    }

    func test_missingKeyAfterProvisioningIsMismatch() {
        // No key, but we provisioned one before → the key became inaccessible
        // (e.g. a re-signed/stale binary). This must NOT be treated as a fresh
        // install silently — it's a detected mismatch.
        XCTAssertEqual(DatabaseKey.decide(keyPresent: false, previouslyProvisioned: true), .recreateAfterMismatch)
    }
}
