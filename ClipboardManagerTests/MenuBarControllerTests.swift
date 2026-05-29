import XCTest
@testable import ClipboardManager

@MainActor
final class MenuBarControllerTests: XCTestCase {

    func testMenuBarPauseInvokesClosureAndRefreshesIcon() {
        var paused = false
        var lastChoice: PauseChoice?
        let controller = MenuBarController(
            onOpenClipboard: {}, onOpenPreferences: {},
            onPause: { choice in lastChoice = choice; paused = true },
            onResume: { paused = false },
            isPaused: { paused }
        )

        controller.pause15ForTesting()
        XCTAssertEqual(lastChoice, .fifteenMinutes)
        XCTAssertTrue(paused)
        XCTAssertEqual(controller.statusSymbolNameForTesting, "pause.circle")

        controller.resumeForTesting()
        XCTAssertFalse(paused)
        XCTAssertEqual(controller.statusSymbolNameForTesting, "doc.on.clipboard")
    }
}
