import XCTest
@testable import ClipboardManager

@MainActor
final class ScreenshotImporterLifecycleTests: XCTestCase {

    func testImporterDeallocatesWhenReleased() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        let blobs = try BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ss-life-\(UUID().uuidString)", isDirectory: true))
        weak var weakRef: ScreenshotImporter?
        autoreleasepool {
            let importer = ScreenshotImporter(store: store, blobStore: blobs)
            weakRef = importer
            XCTAssertNotNil(weakRef)
        }
        XCTAssertNil(weakRef, "ScreenshotImporter leaked — deinit did not run")
    }
}
