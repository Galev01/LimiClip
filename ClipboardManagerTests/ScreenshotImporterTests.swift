import XCTest
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
@testable import ClipboardManager

@MainActor
final class ScreenshotImporterTests: XCTestCase {

    func test_importFile_recordsImageItem() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        let blobDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shots-\(UUID().uuidString)", isDirectory: true)
        let blobStore = try BlobStore(rootDirectory: blobDir)
        let importer = ScreenshotImporter(store: store, blobStore: blobStore, settings: { Settings() })

        let pngURL = blobDir.appendingPathComponent("Screenshot.png")
        try Self.writeTestPNG(to: pngURL)

        let item = try importer.importFile(at: pngURL)

        XCTAssertNotNil(item)
        XCTAssertEqual(item?.kind, "image")
        XCTAssertNotNil(item?.blobPath)
        XCTAssertEqual(try store.recentItems(limit: 10).filter { $0.kind == "image" }.count, 1)
    }

    func test_importFile_dedupesIdenticalScreenshots() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        let blobStore = try BlobStore(rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("shots-\(UUID().uuidString)", isDirectory: true))
        let importer = ScreenshotImporter(store: store, blobStore: blobStore, settings: { Settings() })
        let pngURL = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshot-\(UUID().uuidString).png")
        try Self.writeTestPNG(to: pngURL)

        _ = try importer.importFile(at: pngURL)
        _ = try importer.importFile(at: pngURL)

        XCTAssertEqual(try store.recentItems(limit: 10).filter { $0.kind == "image" }.count, 1)
    }

    static func writeTestPNG(to url: URL) throws {
        let width = 2, height = 2
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "test", code: 1) }
    }

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
