import XCTest
@testable import ClipboardManager

final class VideoReferenceTests: XCTestCase {

    func test_jsonRoundTrip() throws {
        let ref = VideoReference(
            path: "/Users/gal/Movies/recording-1700000000.mov",
            name: "recording-1700000000.mov",
            byteSize: 12_345_678,
            modifiedAt: 1_700_000_000,
            durationSeconds: 65.0,
            width: 1920,
            height: 1080
        )
        let encoded = try ref.encodedJSON()
        let decoded = try VideoReference.decodingJSON(encoded)
        XCTAssertEqual(decoded, ref)
    }

    func test_formattedDuration() {
        XCTAssertEqual(
            VideoReference(path: "/x", name: "x", byteSize: 1, modifiedAt: 0,
                           durationSeconds: 65, width: 1, height: 1).formattedDuration,
            "1:05")
        XCTAssertEqual(
            VideoReference(path: "/x", name: "x", byteSize: 1, modifiedAt: 0,
                           durationSeconds: 5, width: 1, height: 1).formattedDuration,
            "0:05")
    }
}
