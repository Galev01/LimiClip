import XCTest
@testable import ClipboardManager

final class FileReferenceTests: XCTestCase {

    func testRoundTripsThroughJSON() throws {
        let ref = FileReference(
            path: "/Users/gal/Documents/Q2 Report.pdf",
            name: "Q2 Report.pdf",
            byteSize: 2_457_600,
            modifiedAt: 1_700_000_000
        )
        let encoded = try ref.encodedJSON()
        let decoded = try FileReference.decodingJSON(encoded)
        XCTAssertEqual(decoded, ref)
    }

    func testExtensionExtraction() {
        let pdf = FileReference(path: "/a/b/Q2 Report.pdf", name: "Q2 Report.pdf", byteSize: 1, modifiedAt: 1)
        XCTAssertEqual(pdf.fileExtension, "pdf")

        let noExt = FileReference(path: "/a/b/Makefile", name: "Makefile", byteSize: 1, modifiedAt: 1)
        XCTAssertEqual(noExt.fileExtension, "")

        let upper = FileReference(path: "/a/b/PHOTO.JPG", name: "PHOTO.JPG", byteSize: 1, modifiedAt: 1)
        XCTAssertEqual(upper.fileExtension, "jpg")
    }

    func testHumanReadableSize() {
        XCTAssertEqual(FileReference(path: "/x", name: "x", byteSize: 1024, modifiedAt: 0).formattedSize, "1 KB")
        XCTAssertEqual(FileReference(path: "/x", name: "x", byteSize: 1_500_000, modifiedAt: 0).formattedSize, "1.5 MB")
        XCTAssertEqual(FileReference(path: "/x", name: "x", byteSize: 0, modifiedAt: 0).formattedSize, "Zero bytes")
    }
}
