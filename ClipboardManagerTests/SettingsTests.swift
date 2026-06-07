import XCTest
@testable import ClipboardManager

final class SettingsTests: XCTestCase {

    /// We exercise a private UserDefaults instance so tests don't pollute the
    /// real app's settings.
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "settings-tests-\(UUID().uuidString)")
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "")
    }

    func testAppearanceDefaultIsSystem() {
        XCTAssertEqual(Settings(defaults: defaults).appearance, .system)
    }

    func testAppearanceRoundtrips() {
        let s = Settings(defaults: defaults)
        s.appearance = .dark
        XCTAssertEqual(Settings(defaults: defaults).appearance, .dark)
        s.appearance = .light
        XCTAssertEqual(Settings(defaults: defaults).appearance, .light)
    }

    func testHistoryLimitDefaultIs100() {
        XCTAssertEqual(Settings(defaults: defaults).historyLimit, 100)
    }

    func testHistoryLimitRoundtrips() {
        let s = Settings(defaults: defaults)
        s.historyLimit = 1000
        XCTAssertEqual(Settings(defaults: defaults).historyLimit, 1000)
    }

    func testRetentionDaysDefaultIs90() {
        XCTAssertEqual(Settings(defaults: defaults).retentionDays, 90)
    }

    func testShowHoverPreviewDefaultIsTrue() {
        XCTAssertTrue(Settings(defaults: defaults).showHoverPreview)
    }

    func testShowHoverPreviewRoundtrips() {
        let s = Settings(defaults: defaults)
        s.showHoverPreview = false
        XCTAssertFalse(Settings(defaults: defaults).showHoverPreview)
    }

    func testAppearanceEnumStableRawValues() {
        // External code (UI bindings) may rely on these — keep them stable.
        XCTAssertEqual(AppAppearance.system.rawValue, "system")
        XCTAssertEqual(AppAppearance.light.rawValue, "light")
        XCTAssertEqual(AppAppearance.dark.rawValue, "dark")
    }

    func testCompactModeDefaultIsFalse() {
        XCTAssertFalse(Settings(defaults: defaults).compactMode)
    }

    func testCompactModeRoundtrips() {
        let s = Settings(defaults: defaults)
        s.compactMode = true
        XCTAssertTrue(Settings(defaults: defaults).compactMode)
        s.compactMode = false
        XCTAssertFalse(Settings(defaults: defaults).compactMode)
    }

    func testStrictCaptureModeDefaultIsFalse() {
        XCTAssertFalse(Settings(defaults: defaults).strictCaptureMode)
    }

    func testStrictCaptureModeRoundtrips() {
        let s = Settings(defaults: defaults)
        s.strictCaptureMode = true
        XCTAssertTrue(Settings(defaults: defaults).strictCaptureMode)
        s.strictCaptureMode = false
        XCTAssertFalse(Settings(defaults: defaults).strictCaptureMode)
    }

    func testSaveScreenshotsDefaultIsFalse() {
        XCTAssertFalse(Settings(defaults: defaults).saveScreenshots)
    }

    func testSaveScreenshotsRoundtrips() {
        let s = Settings(defaults: defaults)
        s.saveScreenshots = true
        XCTAssertTrue(Settings(defaults: defaults).saveScreenshots)
        s.saveScreenshots = false
        XCTAssertFalse(Settings(defaults: defaults).saveScreenshots)
    }

    func testSaveScreenshotsKeyIsStable() {
        XCTAssertEqual(Settings.Key.saveScreenshots, "saveScreenshots")
    }

    func test_captureScreenshotFiles_defaultsOn() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        XCTAssertTrue(settings.captureScreenshotFiles)
    }

    func test_captureScreenshotFiles_roundTrips() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        settings.captureScreenshotFiles = false
        XCTAssertFalse(settings.captureScreenshotFiles)
    }
}
