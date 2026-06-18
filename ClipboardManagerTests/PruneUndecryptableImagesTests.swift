import XCTest
import CoreGraphics
@testable import ClipboardManager

final class PruneUndecryptableImagesTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prune-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// An image row whose blob can be read is kept; one whose blob is
    /// undecryptable/corrupt is pruned (row + blob removed).
    func test_prunesOnlyUnreadableImageRows() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        // A real cipher so a corrupt sealed blob genuinely fails to decrypt.
        let cipher = FieldCipher(masterKeyData: Data(repeating: 0xAB, count: 32))
        let blobStore = try BlobStore(rootDirectory: tempRoot, cipher: cipher)

        // Good image: a real (sealed) blob that reads back fine.
        let goodPath = try blobStore.write(data: Data("good-png".utf8), fileExtension: "png")
        let good = try store.recordImage(
            contentHash: "goodhash", blobPath: goodPath,
            dimensions: CGSize(width: 10, height: 10), byteSize: 8,
            sourceApp: "Test", sourceBundleId: nil)
        XCTAssertNotNil(good)

        // Bad image: write a blob, then corrupt the on-disk file so decrypt
        // throws (GCM magic present but the body is garbage).
        let badPath = try blobStore.write(data: Data("will-be-corrupted".utf8), fileExtension: "png")
        let bad = try store.recordImage(
            contentHash: "badhash", blobPath: badPath,
            dimensions: CGSize(width: 20, height: 20), byteSize: 17,
            sourceApp: "Test", sourceBundleId: nil)
        let badId = try XCTUnwrap(bad?.id)
        let badURL = tempRoot.appendingPathComponent(badPath)
        try (FieldCipher.blobMagic + Data([0xDE, 0xAD, 0xBE, 0xEF])).write(to: badURL)
        XCTAssertThrowsError(try blobStore.read(relativePath: badPath))

        let pruned = try store.pruneUndecryptableImages(blobStore: blobStore)

        XCTAssertEqual(pruned, 1)
        let remaining = try store.recentItems(limit: 10)
        XCTAssertEqual(remaining.compactMap(\.id), [good?.id].compactMap { $0 })
        XCTAssertFalse(remaining.contains { $0.id == badId })
    }
}
