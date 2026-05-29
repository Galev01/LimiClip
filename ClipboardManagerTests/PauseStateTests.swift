import XCTest
@testable import ClipboardManager

final class PauseStateTests: XCTestCase {

    func testPauseChoiceFifteenMinutesAddsCorrectInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let until = PauseChoice.fifteenMinutes.pausedUntil(from: now)
        XCTAssertEqual(until.timeIntervalSince(now), 15 * 60, accuracy: 0.001)
    }

    func testPauseChoiceOneHourAddsCorrectInterval() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let until = PauseChoice.oneHour.pausedUntil(from: now)
        XCTAssertEqual(until.timeIntervalSince(now), 60 * 60, accuracy: 0.001)
    }

    func testPauseChoiceUntilResumedIsDistantFuture() {
        XCTAssertEqual(PauseChoice.untilResumed.pausedUntil(from: Date()), .distantFuture)
    }

    func testIsPausedTrueWhenUntilInFuture() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(PauseState.isPaused(pausedUntil: now.addingTimeInterval(10), now: now))
        XCTAssertFalse(PauseState.isPaused(pausedUntil: now.addingTimeInterval(-10), now: now))
        XCTAssertFalse(PauseState.isPaused(pausedUntil: .distantPast, now: now))
    }

    func testStatusSymbolDiffersByPausedState() {
        XCTAssertEqual(PauseState.statusSymbolName(isPaused: false), "doc.on.clipboard")
        XCTAssertEqual(PauseState.statusSymbolName(isPaused: true), "pause.circle")
        XCTAssertNotEqual(PauseState.statusSymbolName(isPaused: true), PauseState.statusSymbolName(isPaused: false))
    }

    func testResumeDateIsDistantPast() {
        XCTAssertEqual(PauseState.resumeDate, .distantPast)
        XCTAssertFalse(PauseState.isPaused(pausedUntil: PauseState.resumeDate, now: Date()))
    }

    func testMenuTitlesCoverAllChoices() {
        for choice in PauseChoice.allCases {
            XCTAssertFalse(choice.menuTitle.isEmpty)
        }
        XCTAssertEqual(PauseChoice.allCases.count, 3)
    }
}
