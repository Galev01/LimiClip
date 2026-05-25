import XCTest
import AppKit
@testable import ClipboardManager

@MainActor
final class PasteInjectorTests: XCTestCase {

    private var pasteboard: NSPasteboard!
    private var blobs: BlobStore!

    override func setUp() async throws {
        try await super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
        blobs = try BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("paste-tests-\(UUID().uuidString)", isDirectory: true))
    }

    override func tearDown() async throws {
        pasteboard?.releaseGlobally()
        try await super.tearDown()
    }

    private func makeTextItem(_ body: String) -> Item {
        Item(
            id: 1, kind: "text", subtype: "plain", contentHash: "h",
            body: body, blobPath: nil, dimensions: nil, byteSize: body.utf8.count,
            sourceApp: nil, sourceBundleId: nil,
            createdAt: Int64(Date().timeIntervalSince1970),
            pinned: false, snippetId: nil, deletedAt: nil
        )
    }

    func testWritesTextToPasteboard() throws {
        let injector = PasteInjector(pasteboard: pasteboard, blobStore: blobs)
        try injector.writeToPasteboard(item: makeTextItem("hello"))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
    }

    func testWritesTextAsPlainStripsRTF() throws {
        let injector = PasteInjector(pasteboard: pasteboard, blobStore: blobs)
        try injector.writeToPasteboard(item: makeTextItem("hi"), asPlainText: true)
        XCTAssertEqual(pasteboard.string(forType: .string), "hi")
        XCTAssertFalse(pasteboard.types?.contains(.rtf) ?? false)
    }

    func testWritesImageFromBlob() throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let png = rep.representation(using: .png, properties: [:])!
        let relPath = try blobs.write(data: png, fileExtension: "png")

        let image = Item(
            id: 2, kind: "image", subtype: nil, contentHash: "h",
            body: relPath, blobPath: relPath, dimensions: "4x4", byteSize: png.count,
            sourceApp: nil, sourceBundleId: nil,
            createdAt: Int64(Date().timeIntervalSince1970),
            pinned: false, snippetId: nil, deletedAt: nil
        )
        let injector = PasteInjector(pasteboard: pasteboard, blobStore: blobs)
        try injector.writeToPasteboard(item: image)
        XCTAssertNotNil(pasteboard.data(forType: .png))
    }

    func testWritesFileURL() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("paste-injector-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let ref = FileReference(path: tmp.path, name: tmp.lastPathComponent,
                                byteSize: 1, modifiedAt: 0)
        let body = try ref.encodedJSON()
        let file = Item(
            id: 3, kind: "file", subtype: nil, contentHash: "h",
            body: body, blobPath: nil, dimensions: nil, byteSize: 1,
            sourceApp: nil, sourceBundleId: nil,
            createdAt: Int64(Date().timeIntervalSince1970),
            pinned: false, snippetId: nil, deletedAt: nil
        )
        let injector = PasteInjector(pasteboard: pasteboard, blobStore: blobs)
        try injector.writeToPasteboard(item: file)

        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(urls?.first?.path, tmp.path)
    }
}
