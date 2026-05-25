import XCTest
import AppKit
@testable import ClipboardManager

@MainActor
final class PasteboardMonitorTests: XCTestCase {

    private var pasteboard: NSPasteboard!
    private var store: ClipboardStore!
    private var monitor: PasteboardMonitor!

    override func setUp() async throws {
        try await super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
        store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    }

    override func tearDown() async throws {
        monitor?.stop()
        pasteboard?.releaseGlobally()
        try await super.tearDown()
    }

    func testCapturesNewTextOnPasteboardChange() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()  // baseline snapshot

        pasteboard.clearContents()
        pasteboard.setString("hello pasteboard", forType: .string)

        monitor.tickForTesting()

        XCTAssertEqual(try store.recentItems(limit: 5).map(\.body), ["hello pasteboard"])
    }

    func testSkipsConcealedItems() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()

        pasteboard.clearContents()
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        pasteboard.setData(Data("don't capture me".utf8), forType: concealed)
        pasteboard.setString("don't capture me", forType: .string)

        monitor.tickForTesting()

        XCTAssertEqual(try store.countItems(), 0)
    }

    func testSkipsFromExcludedBundle() async throws {
        try store.addExclusion(bundleId: "com.evil.copier", name: "Evil")

        monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            store: store,
            frontmostApp: { ("Evil", "com.evil.copier") }
        )
        monitor.tickForTesting()

        pasteboard.clearContents()
        pasteboard.setString("secret", forType: .string)
        monitor.tickForTesting()

        XCTAssertEqual(try store.countItems(), 0)
    }

    func testPauseBypassesCapture() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()

        monitor.pause(until: Date().addingTimeInterval(60))

        pasteboard.clearContents()
        pasteboard.setString("while paused", forType: .string)
        monitor.tickForTesting()

        XCTAssertEqual(try store.countItems(), 0)

        // Lift pause and re-copy.
        monitor.pause(until: Date.distantPast)
        pasteboard.clearContents()
        pasteboard.setString("after pause", forType: .string)
        monitor.tickForTesting()
        XCTAssertEqual(try store.recentItems(limit: 5).map(\.body), ["after pause"])
    }

    func testCapturesImage() async throws {
        let blobs = try BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("monitor-tests-\(UUID().uuidString)", isDirectory: true))
        monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            store: store,
            blobStore: blobs,
            frontmostApp: { (nil, nil) }
        )
        monitor.tickForTesting()

        pasteboard.clearContents()
        // Build a 20x10 PNG via NSBitmapImageRep (Retina-safe).
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 10).fill()
        NSGraphicsContext.restoreGraphicsState()
        let pngData = rep.representation(using: .png, properties: [:])!
        pasteboard.setData(pngData, forType: .png)

        monitor.tickForTesting()

        let items = try store.recentItems(limit: 5)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, "image")
        XCTAssertEqual(items.first?.dimensions, "20x10")
        XCTAssertNotNil(items.first?.blobPath)
    }

    func testCapturesFileURL() async throws {
        // Create a real temporary file so the modification date + size are real.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clipboard-test-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()

        pasteboard.clearContents()
        pasteboard.writeObjects([tmp as NSURL])

        monitor.tickForTesting()

        let items = try store.recentItems(limit: 5)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, "file")
        let ref = try FileReference.decodingJSON(items.first!.body)
        XCTAssertEqual(ref.name, tmp.lastPathComponent)
        XCTAssertEqual(ref.path, tmp.path)
    }
}
