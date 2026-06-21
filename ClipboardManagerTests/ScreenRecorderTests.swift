import XCTest
import CoreGraphics
@testable import ClipboardManager

final class ScreenRecorderTests: XCTestCase {

    func test_argumentsRegionNoAudio() {
        let args = ScreenRecorder.arguments(
            globalRect: CGRect(x: 10, y: 20, width: 300, height: 200),
            audio: false,
            outputPath: "/tmp/x.mov")
        XCTAssertEqual(args, ["-v", "-R10,20,300,200", "/tmp/x.mov"])
    }

    func test_argumentsWithAudioIncludesG() {
        let args = ScreenRecorder.arguments(
            globalRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            audio: true,
            outputPath: "/tmp/y.mov")
        XCTAssertTrue(args.contains("-g"))
    }
}
