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

    func testMonitorDropsOversizedPastedText() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()  // baseline snapshot

        let oversized = String(repeating: "x", count: ClipboardStore.maxTextBytes + 1)
        pasteboard.clearContents()
        pasteboard.setString(oversized, forType: .string)
        monitor.tickForTesting()

        XCTAssertEqual(try store.countItems(), 0)
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

    func testCapturesLargeTiffImage() async throws {
        // Copies from Preview/Finder/native apps arrive as UNCOMPRESSED TIFF —
        // a modest Retina screenshot is 15-60 MB of raw bytes. The stored blob
        // is the ≤800px thumbnail, so raw size must not be the disk gate.
        let blobs = try BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("monitor-tests-\(UUID().uuidString)", isDirectory: true))
        monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            store: store,
            blobStore: blobs,
            frontmostApp: { (nil, nil) }
        )
        monitor.tickForTesting()

        // 2200x1400 RGBA ≈ 12.3 MB uncompressed — over the old 10 MB raw cap.
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2200, pixelsHigh: 1400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let tiffData = rep.tiffRepresentation!
        XCTAssertGreaterThan(tiffData.count, 10 * 1024 * 1024, "test premise: TIFF must exceed 10 MB")

        pasteboard.clearContents()
        pasteboard.setData(tiffData, forType: .tiff)
        monitor.tickForTesting()

        let items = try store.recentItems(limit: 5)
        XCTAssertEqual(items.count, 1, "a normal Retina-sized TIFF copy must be captured")
        XCTAssertEqual(items.first?.kind, "image")
        XCTAssertEqual(items.first?.dimensions, "2200x1400")
    }

    func testExcludedImageLeavesNoOrphanBlob() async throws {
        let blobRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("monitor-tests-\(UUID().uuidString)", isDirectory: true)
        let blobs = try BlobStore(rootDirectory: blobRoot)
        try store.addExclusion(bundleId: "com.evil.copier", name: "Evil")
        monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            store: store,
            blobStore: blobs,
            frontmostApp: { ("Evil", "com.evil.copier") }
        )
        monitor.tickForTesting()

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        pasteboard.clearContents()
        pasteboard.setData(rep.representation(using: .png, properties: [:])!, forType: .png)
        monitor.tickForTesting()

        XCTAssertEqual(try store.countItems(), 0)
        let leftover = try FileManager.default
            .subpathsOfDirectory(atPath: blobRoot.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(leftover, [], "dropped capture must not leave an orphaned blob on disk")
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

    // MARK: - Concealed marker types

    func testSkipsTransientItems() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()
        pasteboard.clearContents()
        pasteboard.setData(Data("ephemeral".utf8), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.setString("ephemeral", forType: .string)
        monitor.tickForTesting()
        XCTAssertEqual(try store.countItems(), 0)
    }

    func testSkipsPasteboardGeneratorItems() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()
        pasteboard.clearContents()
        pasteboard.setData(Data("generated".utf8), forType: NSPasteboard.PasteboardType("Pasteboard generator type"))
        pasteboard.setString("generated", forType: .string)
        monitor.tickForTesting()
        XCTAssertEqual(try store.countItems(), 0)
    }

    func testSkipsAutoGeneratedItems() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()
        pasteboard.clearContents()
        pasteboard.setData(Data("auto generated".utf8), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        pasteboard.setString("auto generated", forType: .string)
        monitor.tickForTesting()
        XCTAssertEqual(try store.countItems(), 0)
    }

    func testSkipsAllConcealedMarkerTypes() async throws {
        let markers = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
            "Pasteboard generator type",
        ]
        for marker in markers {
            let pb = NSPasteboard.withUniqueName()
            defer { pb.releaseGlobally() }
            let local = PasteboardMonitor(pasteboard: pb, store: store, frontmostApp: { (nil, nil) })
            local.tickForTesting()
            pb.clearContents()
            pb.setData(Data("payload for \(marker)".utf8), forType: NSPasteboard.PasteboardType(marker))
            pb.setString("payload for \(marker)", forType: .string)
            local.tickForTesting()
            local.stop()
            XCTAssertEqual(try store.countItems(), 0, "marker \(marker) should be skipped")
        }
    }

    // MARK: - Strict capture (fail-closed on unknown source app)

    func testStrictModeDropsCaptureWhenBundleIdNil() async throws {
        let d = UserDefaults(suiteName: "strict-on-\(UUID().uuidString)")!
        d.set(true, forKey: Settings.Key.strictCaptureMode)
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store,
                                    frontmostApp: { (nil, nil) }, settings: { Settings(defaults: d) })
        monitor.tickForTesting()
        pasteboard.clearContents()
        pasteboard.setString("unknown source secret", forType: .string)
        monitor.tickForTesting()
        XCTAssertEqual(try store.countItems(), 0)
    }

    func testStrictModeStillCapturesWhenBundleIdKnown() async throws {
        let d = UserDefaults(suiteName: "strict-on-known-\(UUID().uuidString)")!
        d.set(true, forKey: Settings.Key.strictCaptureMode)
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store,
                                    frontmostApp: { ("Safari", "com.apple.Safari") }, settings: { Settings(defaults: d) })
        monitor.tickForTesting()
        pasteboard.clearContents()
        pasteboard.setString("from a known app", forType: .string)
        monitor.tickForTesting()
        XCTAssertEqual(try store.recentItems(limit: 5).map(\.body), ["from a known app"])
    }

    func testNonStrictModeCapturesWhenBundleIdNil() async throws {
        let d = UserDefaults(suiteName: "strict-off-\(UUID().uuidString)")!
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store,
                                    frontmostApp: { (nil, nil) }, settings: { Settings(defaults: d) })
        monitor.tickForTesting()
        pasteboard.clearContents()
        pasteboard.setString("unknown but allowed", forType: .string)
        monitor.tickForTesting()
        XCTAssertEqual(try store.recentItems(limit: 5).map(\.body), ["unknown but allowed"])
    }

    func testStrictModeDropsImageWithNilBundleId() async throws {
        let blobs = try BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("strict-img-\(UUID().uuidString)", isDirectory: true))
        let d = UserDefaults(suiteName: "strict-img-\(UUID().uuidString)")!
        d.set(true, forKey: Settings.Key.strictCaptureMode)
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, blobStore: blobs,
                                    frontmostApp: { (nil, nil) }, settings: { Settings(defaults: d) })
        monitor.tickForTesting()
        pasteboard.clearContents()
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 10).fill()
        NSGraphicsContext.restoreGraphicsState()
        pasteboard.setData(rep.representation(using: .png, properties: [:])!, forType: .png)
        monitor.tickForTesting()
        XCTAssertEqual(try store.countItems(), 0)
    }

    // MARK: - Pause exposure + screenshot gating

    func testMonitorExposesPausedState() async throws {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let s = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        let m = PasteboardMonitor(pasteboard: pb, store: s, frontmostApp: { (nil, nil) })
        XCTAssertFalse(m.isPaused)
        m.pause(until: Date().addingTimeInterval(60))
        XCTAssertTrue(m.isPaused)
        XCTAssertGreaterThan(m.pausedUntilDate, Date())
        m.pause(until: PauseState.resumeDate)
        XCTAssertFalse(m.isPaused)
    }

    func testTickWhilePausedConsumesChangeCountPermanently() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()  // baseline

        monitor.pause(until: Date().addingTimeInterval(60))
        pasteboard.clearContents()
        pasteboard.setString("screenshot-stand-in", forType: .string)
        monitor.tickForTesting()  // observed while paused -> consumed, not recorded
        XCTAssertEqual(try store.countItems(), 0)

        // Lift pause without changing the pasteboard: must not retroactively record.
        monitor.pause(until: Date.distantPast)
        monitor.tickForTesting()
        XCTAssertEqual(try store.countItems(), 0)

        // A genuinely new copy after the pause is captured normally.
        pasteboard.clearContents()
        pasteboard.setString("after pause real copy", forType: .string)
        monitor.tickForTesting()
        XCTAssertEqual(try store.recentItems(limit: 5).map(\.body), ["after pause real copy"])
    }

    // MARK: - Transient empty read retry (first ⌘C not lost)

    func test_emptyPasteboardReadDoesNotBurnChangeCount() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()  // baseline snapshot

        // App bumped changeCount (declaring a type) but data not yet written —
        // a transient empty read. declareTypes bumps changeCount once.
        pasteboard.declareTypes([.string], owner: nil)
        monitor.tickForTesting()
        XCTAssertEqual(try store.recentItems(limit: 10).count, 0)

        // Data arrives on the next poll for the SAME change count. Writing a
        // value for an already-declared type does not bump changeCount.
        pasteboard.setString("hello", forType: .string)
        monitor.tickForTesting()
        let items = try store.recentItems(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.body, "hello")
    }

    func test_persistentlyEmptyChangeCountGivesUpAfterRetryBudget() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()  // baseline

        pasteboard.declareTypes([.string], owner: nil)
        // Budget is 3 empty retries; tick more than that.
        for _ in 0..<6 { monitor.tickForTesting() }
        // Now content appears for the SAME changeCount — already given up, so ignored.
        pasteboard.setString("late", forType: .string)
        monitor.tickForTesting()
        XCTAssertEqual(try store.recentItems(limit: 10).count, 0)
    }

    func testUnpausedMonitorRecordsScreenshotImage() async throws {
        let blobs = try BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("monitor-tests-\(UUID().uuidString)", isDirectory: true))
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, blobStore: blobs, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()
        pasteboard.clearContents()
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
        pasteboard.setData(rep.representation(using: .png, properties: [:])!, forType: .png)
        monitor.tickForTesting()
        XCTAssertEqual(try store.recentItems(limit: 5).count, 1)
        XCTAssertEqual(try store.recentItems(limit: 5).first?.kind, "image")
    }
}
