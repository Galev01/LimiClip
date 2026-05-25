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

    func testIgnoresImagesInPhase2() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()

        pasteboard.clearContents()
        let tinyTIFF: Data = {
            let image = NSImage(size: NSSize(width: 1, height: 1))
            image.lockFocus()
            NSColor.black.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1))
            image.unlockFocus()
            return image.tiffRepresentation ?? Data()
        }()
        pasteboard.setData(tinyTIFF, forType: .tiff)

        monitor.tickForTesting()
        XCTAssertEqual(try store.countItems(), 0)
    }
}
