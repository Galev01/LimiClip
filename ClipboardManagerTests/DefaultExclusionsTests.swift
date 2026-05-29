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

    func testIncludesApplePasswordsApp() {
        // macOS Sequoia standalone Passwords app. Verified CFBundleIdentifier
        // from /System/Applications/Passwords.app == "com.apple.Passwords".
        // NOTE/LIMITATION: this only excludes copies made from the Passwords
        // app process itself. Passwords filled/copied via Safari/Chrome AutoFill
        // or the iCloud Keychain popover carry the browser's / system UI bundle
        // id and therefore cannot be bundle-excluded here.
        let bundles = DefaultExclusions.list.map(\.bundleId)
        XCTAssertTrue(bundles.contains("com.apple.Passwords"),
                      "DefaultExclusions must seed the macOS Passwords app")
    }

    func testApplePasswordsEntryHasExpectedName() {
        let entry = DefaultExclusions.list.first { $0.bundleId == "com.apple.Passwords" }
        XCTAssertEqual(entry?.name, "Passwords")
    }

    func testApplePasswordsDistinctFromKeychainAccess() {
        let bundles = DefaultExclusions.list.map(\.bundleId)
        XCTAssertTrue(bundles.contains("com.apple.Passwords"))
        XCTAssertTrue(bundles.contains("com.apple.keychainaccess"))
        XCTAssertNotEqual("com.apple.Passwords", "com.apple.keychainaccess")
    }
}
