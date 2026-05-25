# Clipboard Manager — Phase 3 Implementation Plan (Images & Files)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make image and file copies show up as cards in the drawer. Screenshots and copied images appear as thumbnails. Files copied from Finder appear with a file icon + filename. The "ignored in Phase 2" branch of the monitor goes away.

**Architecture:**
- `BlobStore` owns the on-disk thumbnail directory: `~/Library/Application Support/Clipboard Manager/blobs/<aa>/<bb>/<uuid>.png` (sharded two levels deep by leading hex chars of the UUID). All I/O is synchronous file ops via `FileManager` and `Data`.
- `ImageProcessor` is a pure function: take a `Data` blob (TIFF/PNG/JPEG), produce a downsampled PNG `Data` (≤ 800 px max dimension, sRGB) plus the original `pixelSize`.
- `FileReference` is a `Codable` struct describing a copied Finder file: `path`, `name`, `byteSize`, `modifiedAt`.
- `ClipboardStore` gains `recordImage(...)` and `recordFile(...)`. They share the same dedupe-by-hash mechanism as text — image dedupe uses SHA256 of the original bytes; file dedupe uses SHA256 of the path string (a re-copy of the same file at the same path is treated as identical).
- `PasteboardMonitor` adopts a kind-priority router on every change: **file URL → image → text**. The pre-existing privacy and exclusion checks fire first.
- `ClipboardCard` learns to render two more kinds: image (loads the thumbnail via `NSImage(contentsOfFile:)`, fills the card minus the footer, shows a dimension badge); file (centered SF Symbol icon based on extension, filename below).

**Tech stack additions:** None. `CoreGraphics`/`ImageIO` is already linked transitively through AppKit; PNG encoding goes via `CGImageDestination`.

**Verification target:** At the end of Phase 3:
- Taking a screenshot (⌘⇧4) puts an image card in the drawer with the correct pixel dimensions shown.
- Right-clicking a file in Finder and choosing Copy makes a file card with the filename + icon.
- Copying the same image twice produces only one card.
- The thumbnail files exist on disk under `blobs/` and are tens of KB each, not megabytes.

---

## File Structure (this phase)

```
ClipboardManager/
├── Store/
│   ├── BlobStore.swift                 (NEW)
│   ├── FileReference.swift             (NEW)
│   └── ClipboardStore.swift            (MODIFIED — recordImage + recordFile)
├── ActionsKit/
│   └── ImageProcessor.swift            (NEW — downsample + PNG encode)
├── Services/
│   └── PasteboardMonitor.swift         (MODIFIED — kind router)
└── UI/Drawer/
    └── ClipboardCard.swift             (MODIFIED — image + file rendering)

ClipboardManagerTests/
├── BlobStoreTests.swift                (NEW)
├── ImageProcessorTests.swift           (NEW)
├── FileReferenceTests.swift            (NEW)
├── ClipboardStoreTests.swift           (MODIFIED — add image + file insert tests)
└── PasteboardMonitorTests.swift        (MODIFIED — add image + file capture tests)
```

---

## Pre-flight

```bash
cd /Users/gal.lev/Clipboard
git log --oneline -1   # should be eab10aa
git tag -l             # should include v0.2.0-phase2
make test 2>&1 | tail -3
```

Expected: 36 tests pass.

---

## Task 1: FileReference value type (TDD)

**Files:**
- Create: `ClipboardManager/Store/FileReference.swift`
- Create: `ClipboardManagerTests/FileReferenceTests.swift`

- [ ] **Step 1: Failing test**

```swift
// ClipboardManagerTests/FileReferenceTests.swift
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
```

- [ ] **Step 2: Verify build fails**

```bash
cd /Users/gal.lev/Clipboard
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `Cannot find 'FileReference' in scope`.

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/Store/FileReference.swift
import Foundation

/// Persisted JSON-in-body representation of a file copied from Finder.
/// We don't dereference the file at copy time — the user could move/rename
/// it later. We only record the path snapshot.
struct FileReference: Codable, Equatable, Sendable {
    let path: String
    let name: String
    let byteSize: Int64
    let modifiedAt: Int64       // unix epoch seconds, file mtime at copy time

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteSize)
    }

    /// Encode to compact JSON for storage in the Item.body column.
    func encodedJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Decode from a JSON string previously produced by `encodedJSON()`.
    static func decodingJSON(_ raw: String) throws -> FileReference {
        guard let data = raw.data(using: .utf8) else {
            throw NSError(domain: "FileReference", code: 1, userInfo: [NSLocalizedDescriptionKey: "non-UTF8 body"])
        }
        return try JSONDecoder().decode(FileReference.self, from: data)
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

Expected: 39 tests (36 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Store/FileReference.swift ClipboardManagerTests/FileReferenceTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "store: FileReference value type + JSON round-trip"
```

---

## Task 2: BlobStore (TDD)

**Files:**
- Create: `ClipboardManager/Store/BlobStore.swift`
- Create: `ClipboardManagerTests/BlobStoreTests.swift`

- [ ] **Step 1: Failing tests**

```swift
// ClipboardManagerTests/BlobStoreTests.swift
import XCTest
@testable import ClipboardManager

final class BlobStoreTests: XCTestCase {

    private var tempRoot: URL!
    private var store: BlobStore!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blobstore-tests-\(UUID().uuidString)", isDirectory: true)
        store = try BlobStore(rootDirectory: tempRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testWriteAndReadRoundtrip() throws {
        let data = Data("png-bytes-pretend".utf8)
        let relPath = try store.write(data: data, fileExtension: "png")
        XCTAssertTrue(relPath.hasSuffix(".png"))
        XCTAssertTrue(relPath.contains("/"))  // sharded

        let loaded = try store.read(relativePath: relPath)
        XCTAssertEqual(loaded, data)
    }

    func testShardingProduces2LevelDirectoryStructure() throws {
        let data = Data("x".utf8)
        let relPath = try store.write(data: data, fileExtension: "png")
        // Expect "ab/cd/uuid.png" — 2 shards of 2 chars each.
        let parts = relPath.split(separator: "/")
        XCTAssertEqual(parts.count, 3, "expected 3 path components, got \(relPath)")
        XCTAssertEqual(parts[0].count, 2)
        XCTAssertEqual(parts[1].count, 2)
    }

    func testWritesAreUniquePerCall() throws {
        let data = Data("identical".utf8)
        let p1 = try store.write(data: data, fileExtension: "png")
        let p2 = try store.write(data: data, fileExtension: "png")
        // BlobStore doesn't dedupe — that's ClipboardStore's job.
        XCTAssertNotEqual(p1, p2)
    }

    func testDeleteRemovesFile() throws {
        let path = try store.write(data: Data([1, 2, 3]), fileExtension: "png")
        try store.delete(relativePath: path)
        XCTAssertThrowsError(try store.read(relativePath: path))
    }

    func testReadMissingFileThrows() {
        XCTAssertThrowsError(try store.read(relativePath: "ff/ee/missing.png"))
    }
}
```

- [ ] **Step 2: Verify build fails**

```bash
make test 2>&1 | tail -10
```

Expected: `Cannot find 'BlobStore' in scope`.

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/Store/BlobStore.swift
import Foundation

/// On-disk binary storage for images (and, later, any binary blob too large
/// to live in the SQLite row). Files are sharded two levels deep by leading
/// hex chars of the UUID-derived filename, so any single directory stays
/// small even with tens of thousands of items:
///
///     <root>/<aa>/<bb>/<uuid>.<ext>
final class BlobStore: @unchecked Sendable {

    private let root: URL
    private let fm: FileManager

    /// Production initializer — uses Application Support / Clipboard Manager / blobs.
    convenience init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = appSupport.appendingPathComponent("Clipboard Manager", isDirectory: true)
                            .appendingPathComponent("blobs", isDirectory: true)
        try self.init(rootDirectory: dir)
    }

    init(rootDirectory: URL, fileManager: FileManager = .default) throws {
        self.root = rootDirectory
        self.fm = fileManager
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    /// Writes data to a freshly-generated sharded path. Returns the relative
    /// path under `root` (e.g. "ab/cd/uuid.png").
    @discardableResult
    func write(data: Data, fileExtension: String) throws -> String {
        let uuid = UUID().uuidString.lowercased()
        let aa = String(uuid.prefix(2))
        let bb = String(uuid.dropFirst(2).prefix(2))
        let relDir = "\(aa)/\(bb)"
        let filename = "\(uuid).\(fileExtension)"
        let relPath = "\(relDir)/\(filename)"

        let fullDir = root.appendingPathComponent(relDir, isDirectory: true)
        try fm.createDirectory(at: fullDir, withIntermediateDirectories: true)
        let fullURL = fullDir.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: fullURL, options: [.atomic])
        return relPath
    }

    func read(relativePath: String) throws -> Data {
        let fullURL = root.appendingPathComponent(relativePath, isDirectory: false)
        return try Data(contentsOf: fullURL)
    }

    func delete(relativePath: String) throws {
        let fullURL = root.appendingPathComponent(relativePath, isDirectory: false)
        try fm.removeItem(at: fullURL)
    }

    /// Absolute file URL — used by SwiftUI's `Image(nsImage:)` via `NSImage(contentsOfFile:)`.
    func absoluteURL(forRelativePath relativePath: String) -> URL {
        root.appendingPathComponent(relativePath, isDirectory: false)
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

Expected: 44 tests (39 + 5 new).

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Store/BlobStore.swift ClipboardManagerTests/BlobStoreTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "store: BlobStore — sharded on-disk binary storage + tests"
```

---

## Task 3: ImageProcessor (TDD)

**Files:**
- Create: `ClipboardManager/ActionsKit/ImageProcessor.swift`
- Create: `ClipboardManagerTests/ImageProcessorTests.swift`

The processor takes raw image bytes from the pasteboard (TIFF, PNG, JPEG) and produces a downsampled PNG suitable for the card thumbnail.

- [ ] **Step 1: Failing tests**

```swift
// ClipboardManagerTests/ImageProcessorTests.swift
import XCTest
import AppKit
@testable import ClipboardManager

final class ImageProcessorTests: XCTestCase {

    private func makeImageData(width: Int, height: Int) -> Data {
        // Solid color image, encoded as PNG via NSImage → CGImage.
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: width, height: height))
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testProcessSmallImagePassesThroughDimensions() throws {
        let png = makeImageData(width: 200, height: 100)
        let result = try ImageProcessor.process(data: png)
        XCTAssertEqual(result.pixelSize.width, 200)
        XCTAssertEqual(result.pixelSize.height, 100)
        XCTAssertGreaterThan(result.thumbnailData.count, 0)
        // Thumbnail PNG is still valid.
        XCTAssertNotNil(NSImage(data: result.thumbnailData))
    }

    func testProcessDownsamplesLargeImage() throws {
        let png = makeImageData(width: 4000, height: 3000)
        let result = try ImageProcessor.process(data: png)
        // Original dimensions are preserved on the result.
        XCTAssertEqual(result.pixelSize.width, 4000)
        XCTAssertEqual(result.pixelSize.height, 3000)
        // But the thumbnail PNG's max side must be ≤ 800.
        let thumb = NSImage(data: result.thumbnailData)!
        let rep = thumb.representations.first as? NSBitmapImageRep ?? NSBitmapImageRep(data: result.thumbnailData)!
        XCTAssertLessThanOrEqual(max(rep.pixelsWide, rep.pixelsHigh), 800)
    }

    func testInvalidDataThrows() {
        let bogus = Data("not an image".utf8)
        XCTAssertThrowsError(try ImageProcessor.process(data: bogus))
    }
}
```

- [ ] **Step 2: Verify build fails**

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/ActionsKit/ImageProcessor.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessor {

    static let maxThumbnailPixels: CGFloat = 800

    enum Failure: Error {
        case unreadable
        case noImage
        case encodeFailed
    }

    struct Result {
        let thumbnailData: Data
        let pixelSize: CGSize
    }

    /// Downsamples (if needed) and re-encodes the input image bytes to a
    /// PNG no larger than `maxThumbnailPixels` on its longest side. The
    /// `pixelSize` reports the ORIGINAL image's pixel dimensions so the UI
    /// can show "4032 × 3024" for a phone photo even though the on-disk
    /// thumbnail is smaller.
    static func process(data: Data) throws -> Result {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Failure.unreadable
        }

        // Read original dimensions from the file's metadata WITHOUT loading
        // the full bitmap. This is cheap.
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else {
            throw Failure.unreadable
        }
        let originalSize = CGSize(width: pixelWidth, height: pixelHeight)

        // Generate a thumbnail capped at maxThumbnailPixels. CGImageSource
        // does this efficiently using its own downsampling pipeline.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxThumbnailPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw Failure.noImage
        }

        // Encode thumbnail to PNG.
        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(outData, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encodeFailed
        }
        CGImageDestinationAddImage(dest, thumb, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw Failure.encodeFailed
        }

        return Result(thumbnailData: outData as Data, pixelSize: originalSize)
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

Expected: 47 tests.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/ActionsKit/ImageProcessor.swift ClipboardManagerTests/ImageProcessorTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "actions: ImageProcessor (downsample to ≤800px PNG)"
```

---

## Task 4: ClipboardStore — recordImage + recordFile

**Files:**
- Modify: `ClipboardManager/Store/ClipboardStore.swift`
- Modify: `ClipboardManagerTests/ClipboardStoreTests.swift`

The store currently has `recordText`. Add `recordImage` and `recordFile` that share the dedupe + change-notification + exclusion logic.

- [ ] **Step 1: Add failing tests** to `ClipboardManagerTests/ClipboardStoreTests.swift` (append before the closing `}`):

```swift
    // MARK: - Phase 3: image + file

    func testRecordImageStoresWithBlobPathAndDimensions() throws {
        let store = try makeStore()
        // imageHash is independent of body; we pass the raw bytes' hash explicitly.
        let imageBytes = Data([0xff, 0xee, 0xdd, 0xcc])
        let inserted = try store.recordImage(
            contentHash: "abc123",
            blobPath: "ab/cd/uuid.png",
            dimensions: CGSize(width: 4032, height: 3024),
            byteSize: imageBytes.count,
            sourceApp: "Screenshot",
            sourceBundleId: nil
        )
        XCTAssertNotNil(inserted)
        XCTAssertEqual(inserted?.kind, "image")
        XCTAssertEqual(inserted?.blobPath, "ab/cd/uuid.png")
        XCTAssertEqual(inserted?.dimensions, "4032x3024")
        XCTAssertEqual(inserted?.body, "ab/cd/uuid.png")
    }

    func testRecordImageDedupesByContentHash() throws {
        let store = try makeStore()
        let a = try store.recordImage(
            contentHash: "samehash",
            blobPath: "aa/bb/first.png", dimensions: CGSize(width: 100, height: 100),
            byteSize: 10, sourceApp: nil, sourceBundleId: nil
        )
        let b = try store.recordImage(
            contentHash: "samehash",
            blobPath: "cc/dd/second.png", dimensions: CGSize(width: 100, height: 100),
            byteSize: 10, sourceApp: nil, sourceBundleId: nil
        )
        XCTAssertEqual(a?.id, b?.id)
        XCTAssertEqual(try store.countItems(), 1)
        // The blobPath of the duplicate insert is the one returned by recordImage,
        // but the caller is responsible for cleaning up the unused blob file.
    }

    func testRecordFileStoresJSONReference() throws {
        let store = try makeStore()
        let ref = FileReference(
            path: "/Users/gal/Documents/spec.pdf",
            name: "spec.pdf",
            byteSize: 1024,
            modifiedAt: 1_700_000_000
        )
        let inserted = try store.recordFile(reference: ref, sourceApp: "Finder", sourceBundleId: "com.apple.finder")
        XCTAssertNotNil(inserted)
        XCTAssertEqual(inserted?.kind, "file")
        let decoded = try FileReference.decodingJSON(inserted!.body)
        XCTAssertEqual(decoded, ref)
    }

    func testRecordFileDedupesByPath() throws {
        let store = try makeStore()
        let ref = FileReference(path: "/x/y/a.pdf", name: "a.pdf", byteSize: 1, modifiedAt: 1)
        let first = try store.recordFile(reference: ref, sourceApp: nil, sourceBundleId: nil)
        let second = try store.recordFile(reference: ref, sourceApp: nil, sourceBundleId: nil)
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(try store.countItems(), 1)
    }
```

- [ ] **Step 2: Verify build fails**

```bash
make test 2>&1 | tail -10
```

Expected: `Value of type 'ClipboardStore' has no member 'recordImage'`.

- [ ] **Step 3: Implement** — add these methods inside the `ClipboardStore` class, after `recordText`:

```swift
    /// Records an image clipboard item. `contentHash` is the SHA256 of the
    /// ORIGINAL image bytes (computed by the caller — the monitor — so we
    /// don't double-hash). On dedupe hit, the existing row's createdAt is
    /// bumped and the new blob path is NOT replaced (caller should delete
    /// the unused new blob).
    @discardableResult
    func recordImage(
        contentHash: String,
        blobPath: String,
        dimensions: CGSize,
        byteSize: Int,
        sourceApp: String?,
        sourceBundleId: String?
    ) throws -> Item? {
        if let bundleId = sourceBundleId, try isExcluded(bundleId: bundleId) {
            Log.app.info("skipping image from excluded bundle: \(bundleId, privacy: .public)")
            return nil
        }
        let now = Int64(Date().timeIntervalSince1970)
        let dimsString = "\(Int(dimensions.width))x\(Int(dimensions.height))"

        let result: Item = try queue.write { db in
            if var existing = try Item
                .filter(Item.Columns.contentHash == contentHash && Item.Columns.deletedAt == nil)
                .fetchOne(db)
            {
                existing.createdAt = now
                try existing.update(db)
                return existing
            }
            var item = Item(
                id: nil,
                kind: "image",
                subtype: nil,
                contentHash: contentHash,
                body: blobPath,
                blobPath: blobPath,
                dimensions: dimsString,
                byteSize: byteSize,
                sourceApp: sourceApp,
                sourceBundleId: sourceBundleId,
                createdAt: now,
                pinned: false,
                snippetId: nil,
                deletedAt: nil
            )
            try item.insert(db)
            return item
        }
        postChange()
        return result
    }

    /// Records a file clipboard item from a `FileReference`. Dedupe is by
    /// path (so re-copying the same file is a no-op).
    @discardableResult
    func recordFile(
        reference: FileReference,
        sourceApp: String?,
        sourceBundleId: String?
    ) throws -> Item? {
        if let bundleId = sourceBundleId, try isExcluded(bundleId: bundleId) {
            Log.app.info("skipping file from excluded bundle: \(bundleId, privacy: .public)")
            return nil
        }
        let now = Int64(Date().timeIntervalSince1970)
        let body = try reference.encodedJSON()
        let hash = Self.hash(reference.path)

        let result: Item = try queue.write { db in
            if var existing = try Item
                .filter(Item.Columns.contentHash == hash && Item.Columns.deletedAt == nil)
                .fetchOne(db)
            {
                existing.createdAt = now
                try existing.update(db)
                return existing
            }
            var item = Item(
                id: nil,
                kind: "file",
                subtype: nil,
                contentHash: hash,
                body: body,
                blobPath: nil,
                dimensions: nil,
                byteSize: Int(reference.byteSize),
                sourceApp: sourceApp,
                sourceBundleId: sourceBundleId,
                createdAt: now,
                pinned: false,
                snippetId: nil,
                deletedAt: nil
            )
            try item.insert(db)
            return item
        }
        postChange()
        return result
    }
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

Expected: 51 tests pass (47 + 4 new).

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Store/ClipboardStore.swift ClipboardManagerTests/ClipboardStoreTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "store: recordImage + recordFile (with dedupe + tests)"
```

---

## Task 5: PasteboardMonitor — kind router (TDD)

**Files:**
- Modify: `ClipboardManager/Services/PasteboardMonitor.swift`
- Modify: `ClipboardManagerTests/PasteboardMonitorTests.swift`

The Phase 2 monitor falls through to "text" for everything that's not concealed. Phase 3 routes by precedence: file URL → image → text.

- [ ] **Step 1: Update the existing Phase 2 test that asserts "images are ignored"**

In `/Users/gal.lev/Clipboard/ClipboardManagerTests/PasteboardMonitorTests.swift`, the test currently named `testIgnoresImagesInPhase2` becomes `testCapturesImage`. Replace its body with:

```swift
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
        let pngData: Data = {
            let image = NSImage(size: NSSize(width: 20, height: 10))
            image.lockFocus()
            NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 20, height: 10))
            image.unlockFocus()
            let tiff = image.tiffRepresentation!
            let rep = NSBitmapImageRep(data: tiff)!
            return rep.representation(using: .png, properties: [:])!
        }()
        pasteboard.setData(pngData, forType: .png)

        monitor.tickForTesting()

        let items = try store.recentItems(limit: 5)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, "image")
        XCTAssertEqual(items.first?.dimensions, "20x10")
        XCTAssertNotNil(items.first?.blobPath)
    }
```

And append a new test:

```swift
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
```

You also need to update the other existing tests so they construct `PasteboardMonitor` with the new `blobStore:` parameter — but since `blobStore` will have a default value (a temp directory), the existing call sites don't need to change. (Confirm this when implementing.)

- [ ] **Step 2: Verify build fails**

```bash
make test 2>&1 | tail -10
```

Expected: build errors about missing `blobStore:` parameter (or related).

- [ ] **Step 3: Modify PasteboardMonitor**

Replace `/Users/gal.lev/Clipboard/ClipboardManager/Services/PasteboardMonitor.swift` with:

```swift
// ClipboardManager/Services/PasteboardMonitor.swift
import AppKit
import Foundation
import CryptoKit

/// Polls `NSPasteboard.changeCount` every 250 ms and records changes into
/// the `ClipboardStore`. The kind router runs after the privacy + exclusion
/// filters, with precedence: file URL → image → text.
@MainActor
final class PasteboardMonitor {

    static let pollInterval: TimeInterval = 0.25

    typealias FrontmostAppProvider = () -> (name: String?, bundleId: String?)

    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let blobStore: BlobStore
    private let frontmostApp: FrontmostAppProvider

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var pausedUntil: Date = .distantPast

    private static let concealedTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("Pasteboard generator type"),
    ]

    init(
        pasteboard: NSPasteboard = .general,
        store: ClipboardStore,
        blobStore: BlobStore? = nil,
        frontmostApp: @escaping FrontmostAppProvider = PasteboardMonitor.defaultFrontmostApp
    ) {
        self.pasteboard = pasteboard
        self.store = store
        // If no blob store was injected, create one rooted at a temp directory.
        // Production code must inject the shared production BlobStore.
        if let blobStore {
            self.blobStore = blobStore
        } else {
            self.blobStore = (try? BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("clipboard-monitor-\(UUID().uuidString)", isDirectory: true)))
                ?? (try! BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))
        }
        self.frontmostApp = frontmostApp
    }

    nonisolated static func defaultFrontmostApp() -> (name: String?, bundleId: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.app.info("pasteboard monitor started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pause(until date: Date) {
        pausedUntil = date
    }

    func tickForTesting() { tick() }

    private func tick() {
        let current = pasteboard.changeCount
        defer { lastChangeCount = current }
        guard current != lastChangeCount else { return }
        guard Date() >= pausedUntil else {
            Log.app.debug("monitor paused, skipping change")
            return
        }
        route()
    }

    /// Decide what kind of item this pasteboard change represents and hand
    /// off to the appropriate capture method.
    private func route() {
        if let types = pasteboard.types, !Set(types).isDisjoint(with: Self.concealedTypes) {
            Log.app.info("skipping concealed pasteboard item")
            return
        }
        let (appName, bundleId) = frontmostApp()

        // 1. File URLs win.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let fileURLs = urls.filter { $0.isFileURL }
            if let first = fileURLs.first {
                captureFile(url: first, appName: appName, bundleId: bundleId)
                return
            }
        }

        // 2. Image types next.
        if let imageType = pickImageType(), let data = pasteboard.data(forType: imageType) {
            captureImage(data: data, appName: appName, bundleId: bundleId)
            return
        }

        // 3. Plain text.
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            do {
                _ = try store.recordText(text, sourceApp: appName, sourceBundleId: bundleId)
            } catch {
                Log.app.error("text record failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func pickImageType() -> NSPasteboard.PasteboardType? {
        let preferred: [NSPasteboard.PasteboardType] = [.png, .tiff]
        guard let available = pasteboard.types else { return nil }
        for t in preferred where available.contains(t) {
            return t
        }
        return nil
    }

    private func captureImage(data: Data, appName: String?, bundleId: String?) {
        do {
            let processed = try ImageProcessor.process(data: data)
            let blobPath = try blobStore.write(data: processed.thumbnailData, fileExtension: "png")
            let hash = Self.hashBytes(data)
            _ = try store.recordImage(
                contentHash: hash,
                blobPath: blobPath,
                dimensions: processed.pixelSize,
                byteSize: data.count,
                sourceApp: appName,
                sourceBundleId: bundleId
            )
        } catch {
            Log.app.error("image capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func captureFile(url: URL, appName: String?, bundleId: String?) {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let ref = FileReference(
                path: url.path,
                name: url.lastPathComponent,
                byteSize: size,
                modifiedAt: Int64(mtime)
            )
            _ = try store.recordFile(reference: ref, sourceApp: appName, sourceBundleId: bundleId)
        } catch {
            Log.app.error("file capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func hashBytes(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -15
```

Expected: 52 tests (51 + 1 new file test; the renamed image test still counts as 1).

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Services/PasteboardMonitor.swift ClipboardManagerTests/PasteboardMonitorTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "monitor: route file/image/text by precedence; capture images + files"
```

---

## Task 6: AppCoordinator — share the production BlobStore

**Files:**
- Modify: `ClipboardManager/App/AppCoordinator.swift`

- [ ] **Step 1: Add BlobStore to the coordinator** so the production monitor uses the shared on-disk directory, not a temp dir.

Replace `/Users/gal.lev/Clipboard/ClipboardManager/App/AppCoordinator.swift` entirely with:

```swift
// ClipboardManager/App/AppCoordinator.swift
import AppKit

@MainActor
final class AppCoordinator {
    private let store: ClipboardStore
    private let blobStore: BlobStore
    private let viewModel: ClipboardViewModel
    private let menuBar: MenuBarController
    private let drawer: DrawerWindowController
    private let hotkey: HotkeyService
    private let monitor: PasteboardMonitor
    private let retention: RetentionJob

    init() throws {
        let store = try ClipboardStore()
        try store.seedDefaultExclusionsIfNeeded()
        self.store = store

        let blobStore = try BlobStore()
        self.blobStore = blobStore

        let viewModel = ClipboardViewModel(store: store)
        self.viewModel = viewModel

        let drawer = DrawerWindowController(viewModel: viewModel)
        self.drawer = drawer

        self.menuBar = MenuBarController { drawer.toggle() }
        self.hotkey = HotkeyService { drawer.toggle() }
        self.monitor = PasteboardMonitor(store: store, blobStore: blobStore)
        self.retention = RetentionJob(store: store)
    }

    func start() {
        Log.coordinator.info("coordinator starting")
        hotkey.start()
        monitor.start()
        retention.start()
    }
}
```

- [ ] **Step 2: Build + run tests**

```bash
make build 2>&1 | tail -5
make test 2>&1 | tail -10
```

Expected: 52 tests still pass.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/App/AppCoordinator.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "wire: AppCoordinator owns the production BlobStore"
```

---

## Task 7: ClipboardCard — render image + file kinds

**Files:**
- Modify: `ClipboardManager/UI/Drawer/ClipboardCard.swift`

The current `ClipboardCard` only renders text. We extend its `content` view-builder to branch on `item.kind`. We also need a `BlobStore` reference so the image card can resolve the blob URL.

Approach: pass the `BlobStore` down via SwiftUI environment.

- [ ] **Step 1: Add a SwiftUI environment key for BlobStore**

Append to `/Users/gal.lev/Clipboard/ClipboardManager/Store/BlobStore.swift`:

```swift

// MARK: - SwiftUI environment

import SwiftUI

private struct BlobStoreKey: EnvironmentKey {
    static let defaultValue: BlobStore? = nil
}

extension EnvironmentValues {
    var blobStore: BlobStore? {
        get { self[BlobStoreKey.self] }
        set { self[BlobStoreKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Provide it from DrawerView**

Edit `/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/DrawerView.swift`. Add a `let blobStore: BlobStore?` property and inject it into the environment:

```swift
struct DrawerView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let blobStore: BlobStore?

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            // ... existing background + gradient ...

            if viewModel.items.isEmpty {
                EmptyStateView()
            } else {
                cardStrip
            }
        }
        // ... existing modifiers ...
        .environment(\.blobStore, blobStore)
    }
    // ... rest unchanged
}
```

The `#Preview` block: update to pass `blobStore: nil`.

- [ ] **Step 3: Update DrawerWindow + DrawerWindowController to thread the BlobStore through**

`/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/DrawerWindow.swift`:

```swift
    init(viewModel: ClipboardViewModel, blobStore: BlobStore?) {
        // ... existing super.init + flags ...
        let host = NSHostingView(rootView: DrawerView(viewModel: viewModel, blobStore: blobStore))
        // ... rest unchanged
    }
```

`/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/DrawerWindowController.swift`:

```swift
    init(viewModel: ClipboardViewModel, blobStore: BlobStore?) {
        self.window = DrawerWindow(viewModel: viewModel, blobStore: blobStore)
        // ... rest unchanged
    }
```

`/Users/gal.lev/Clipboard/ClipboardManager/App/AppCoordinator.swift` (just the drawer line):

```swift
        let drawer = DrawerWindowController(viewModel: viewModel, blobStore: blobStore)
```

- [ ] **Step 4: Extend ClipboardCard.content** to switch on item.kind

Replace the entire body of `/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/ClipboardCard.swift` with:

```swift
// ClipboardManager/UI/Drawer/ClipboardCard.swift
import SwiftUI
import AppKit

struct ClipboardCard: View {
    let item: Item
    @Environment(\.colorScheme) private var scheme
    @Environment(\.blobStore) private var blobStore

    private var dark: Bool { scheme == .dark }

    private var isCode: Bool {
        item.subtype == TextSubtype.code.rawValue || item.subtype == TextSubtype.json.rawValue
    }
    private var isURL: Bool {
        item.subtype == TextSubtype.url.rawValue
    }
    private var isImage: Bool { item.kind == "image" }
    private var isFile: Bool { item.kind == "file" }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))

            footer
        }
        .frame(width: 184, height: 210)
        .background(DesignColors.cardBackground(dark: dark))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var content: some View {
        if isImage {
            imageContent
        } else if isFile {
            fileContent
        } else {
            textContent
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        ZStack(alignment: .bottomTrailing) {
            if let path = item.blobPath,
               let blobStore,
               let nsImage = NSImage(contentsOf: blobStore.absoluteURL(forRelativePath: path)) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [.gray.opacity(0.4), .gray.opacity(0.2)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            if let dims = item.dimensions {
                Text(dims)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.4))
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var fileContent: some View {
        let ref = (try? FileReference.decodingJSON(item.body))
        VStack(spacing: 8) {
            Image(systemName: symbolName(for: ref?.fileExtension ?? ""))
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(colorForExtension(ref?.fileExtension ?? ""))
            Text(ref?.name ?? "Unknown file")
                .font(DesignTypography.cardBody)
                .foregroundStyle(.primary.opacity(dark ? 0.85 : 0.75))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            if let size = ref?.formattedSize {
                Text(size)
                    .font(DesignTypography.cardFooterTime)
                    .foregroundStyle(.primary.opacity(dark ? 0.4 : 0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var textContent: some View {
        Group {
            if isCode {
                Text(item.body)
                    .font(DesignTypography.cardCode)
            } else if isURL {
                Text(item.body)
                    .font(DesignTypography.cardBody)
                    .underline()
            } else {
                Text(item.body)
                    .font(DesignTypography.cardBody)
            }
        }
        .foregroundStyle(.primary.opacity(dark ? 0.8 : 0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .mask(LinearGradient(
            stops: [.init(color: .black, location: 0.65),
                    .init(color: .clear, location: 1.0)],
            startPoint: .top, endPoint: .bottom))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.secondary.opacity(0.6))
                .frame(width: 10, height: 10)
            Text(item.sourceApp ?? "Unknown")
                .font(DesignTypography.cardFooterApp)
                .foregroundStyle(.primary.opacity(dark ? 0.5 : 0.4))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(relativeTime(item.createdAt))
                .font(DesignTypography.cardFooterTime)
                .foregroundStyle(.primary.opacity(dark ? 0.3 : 0.25))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(DesignColors.hairline(dark: dark)),
                 alignment: .top)
    }

    private func symbolName(for ext: String) -> String {
        switch ext {
        case "pdf":                       return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "tiff": return "photo"
        case "mp4", "mov", "m4v":         return "film"
        case "mp3", "wav", "m4a", "aiff": return "music.note"
        case "zip", "tar", "gz", "7z":    return "doc.zipper"
        case "fig":                       return "paintbrush"
        case "sketch":                    return "scribble"
        case "key", "pages", "numbers":   return "doc.text"
        case "xlsx", "csv":               return "tablecells"
        case "docx", "rtf", "txt", "md":  return "doc.text"
        default:                          return "doc"
        }
    }

    private func colorForExtension(_ ext: String) -> Color {
        switch ext {
        case "pdf":                       return .red
        case "fig":                       return .purple
        case "sketch":                    return .orange
        case "key":                       return .blue
        case "xlsx", "csv":               return .green
        case "docx":                      return .blue
        case "zip", "tar", "gz", "7z":    return .gray
        case "png", "jpg", "jpeg", "gif", "heic", "tiff": return .pink
        case "mp4", "mov", "m4v":         return .purple
        default:                          return .secondary
        }
    }

    private func relativeTime(_ epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Text") {
    let preview = Item(
        id: 1, kind: "text", subtype: "plain", contentHash: "abc",
        body: "Hello there, this is some text that wraps onto multiple lines.",
        blobPath: nil, dimensions: nil, byteSize: 100,
        sourceApp: "Messages", sourceBundleId: nil,
        createdAt: Int64(Date().timeIntervalSince1970) - 120,
        pinned: false, snippetId: nil, deletedAt: nil
    )
    return ClipboardCard(item: preview)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("File") {
    let ref = FileReference(path: "/U/x/Q2 Report.pdf", name: "Q2 Report.pdf", byteSize: 2_457_600, modifiedAt: 1)
    let body = try! ref.encodedJSON()
    let preview = Item(
        id: 2, kind: "file", subtype: nil, contentHash: "h",
        body: body, blobPath: nil, dimensions: nil, byteSize: Int(ref.byteSize),
        sourceApp: "Finder", sourceBundleId: nil,
        createdAt: Int64(Date().timeIntervalSince1970) - 30,
        pinned: false, snippetId: nil, deletedAt: nil
    )
    return ClipboardCard(item: preview)
        .padding()
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 5: Build + tests**

```bash
make test 2>&1 | tail -10
```

Expected: 52 tests pass.

- [ ] **Step 6: Commit**

```bash
git add ClipboardManager/Store/BlobStore.swift ClipboardManager/UI/Drawer/ClipboardCard.swift ClipboardManager/UI/Drawer/DrawerView.swift ClipboardManager/UI/Drawer/DrawerWindow.swift ClipboardManager/UI/Drawer/DrawerWindowController.swift ClipboardManager/App/AppCoordinator.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "ui: render image thumbnails + file icons in ClipboardCard"
```

---

## Task 8: Smoke verify + tag v0.3.0

- [ ] **Step 1: Rebuild and relaunch**

```bash
cd /Users/gal.lev/Clipboard
killall ClipboardManager 2>/dev/null; sleep 1
make build 2>&1 | tail -3
APP_DIR=$(xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/ {print $3; exit}')
open -g "$APP_DIR/ClipboardManager.app"
```

- [ ] **Step 2: User verification**

Ask the user to:
1. Press `⌘⇧4`, snip a region of the screen — a card with the screenshot thumbnail should appear in the drawer (`⌘⇧V`).
2. In Finder, right-click a file → Copy → open the drawer — a file card with the SF Symbol icon, filename, and size should appear.
3. Copy the same file twice — only one card.
4. Confirm the existing text capture still works (copy some text in another app).

- [ ] **Step 3: Verify blob files exist on disk**

```bash
ls -lR "$HOME/Library/Application Support/Clipboard Manager/blobs/" | head -20
```

Expected: at least one PNG file under a 2-level shard tree.

- [ ] **Step 4: Tag**

```bash
git tag -a v0.3.0-phase3 -m "Phase 3 complete: image thumbnails + file references in clipboard history"
git log --oneline v0.2.0-phase2..v0.3.0-phase3
```

## Phase 3 — Done criteria

- [ ] `make test` passes (52 tests).
- [ ] Screenshot via ⌘⇧4 appears as a thumbnail card with correct pixel dimensions shown.
- [ ] File copied from Finder appears as a file card with extension-appropriate icon and filename.
- [ ] Re-copying the same image / file does not create a duplicate.
- [ ] Thumbnail files in `blobs/` are sharded two levels deep and are < 200 KB each for typical screenshots.
- [ ] `v0.3.0-phase3` tag exists.

## What's next (Phase 4 preview)

Drawer polish — hover preview popover (full-size image, full text, file metadata after 400 ms), context menu, search field, tabs (All / Text / Images / Files / Pinned), keyboard navigation (arrow keys, `⌘1-9`), and paste injection (Enter → write to pasteboard → simulate ⌘V into the previously-active app → dismiss drawer).
