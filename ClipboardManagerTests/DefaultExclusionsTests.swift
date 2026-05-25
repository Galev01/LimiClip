import XCTest
@testable import ClipboardManager

final class DefaultExclusionsTests: XCTestCase {

    func testIncludesKnownPasswordManagers() {
        let bundles = DefaultExclusions.list.map(\.bundleId)
        XCTAssertTrue(bundles.contains("com.agilebits.onepassword7"))
        XCTAssertTrue(bundles.contains("com.1password.1password8"))
        XCTAssertTrue(bundles.contains("com.bitwarden.desktop"))
        XCTAssertTrue(bundles.contains("com.apple.keychainaccess"))
    }

    func testEveryEntryHasName() {
        for e in DefaultExclusions.list {
            XCTAssertFalse(e.name.isEmpty, "\(e.bundleId) has empty name")
        }
    }

    func testNoDuplicateBundleIds() {
        let bundles = DefaultExclusions.list.map(\.bundleId)
        XCTAssertEqual(bundles.count, Set(bundles).count)
    }
}
