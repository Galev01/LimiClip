import XCTest
@testable import ClipboardManager

@MainActor
final class ScreenshotImporterTests: XCTestCase {

    func test_resolveScreenshotFolder_fallsBackToDesktop() {
        let url = ScreenshotImporter.resolveScreenshotFolder(location: nil)
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        XCTAssertEqual(url.standardizedFileURL, desktop.standardizedFileURL)
    }

    func test_resolveScreenshotFolder_expandsTilde() {
        let url = ScreenshotImporter.resolveScreenshotFolder(location: "~/Pictures/Shots")
        XCTAssertTrue(url.path.hasSuffix("/Pictures/Shots"))
        XCTAssertFalse(url.path.contains("~"))
    }
}
