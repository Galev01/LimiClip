# Copy/Paste Consistency + Image Annotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two clipboard-capture consistency bugs (first ⌘C lost; image previews missing) and add an in-app image annotation editor that can copy, save-to-folder, or save-into-history.

**Architecture:** Part 1 changes `PasteboardMonitor` so a transient empty pasteboard read no longer "burns" a change count — `route()` reports handled-vs-empty and `tick()` only commits on handled, with a bounded retry. Part 2 is debug-driven: diagnose the live install, write a failing regression test at the root-cause layer, then fix. Part 3 adds a UI-free `ImageAnnotator` core (model + PNG flatten) plus a thin SwiftUI editor reachable from an "Annotate" context-menu action on image cards.

**Tech Stack:** Swift, AppKit + SwiftUI, GRDB (SQLite), ImageIO/CoreGraphics, XCTest. Build/test via `make test` (xcodebuild).

## Global Constraints

- Target: macOS app `ClipboardManager`, headless menu-bar app (no main menu).
- Tests run with: `make test` (xcodebuild test on the `ClipboardManager` scheme). Individual tests can't be run standalone without xcodebuild; run the full `make test` (or the test class) after each implementation step.
- `@MainActor` isolation: `PasteboardMonitor`, `ClipboardStore`, `ScreenshotImporter`, coordinators are `@MainActor`. New UI is `@MainActor` by default.
- Image blobs are downsampled thumbnails (≤800px PNG); originals are never persisted. Annotation operates on the thumbnail.
- Logging via `Log.app` / `Log.coordinator` with `privacy:` annotations — never log clipboard contents.
- Encryption: `ClipboardStore` seals body/sourceApp/sourceBundleId via `cipher`; `blobPath` column stays plaintext; blob *bytes* are encrypted by `BlobStore`.
- Commit messages end with the trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## Part 1 — Bug: first ⌘C not captured

### Task 1: `PasteboardMonitor.route()` reports handled-vs-empty; `tick()` retries empty reads

**Files:**
- Modify: `ClipboardManager/Services/PasteboardMonitor.swift`
- Test: `ClipboardManagerTests/PasteboardMonitorTests.swift`

**Interfaces:**
- Produces: a private `enum RouteOutcome { case handled, empty }`; `route()` returns `RouteOutcome`; `tick()` gains retry state `pendingChangeCount: Int` and `pendingAttempts: Int`, plus `static let maxEmptyRetries = 3`.
- Consumes: existing `pasteboard.changeCount`, `route()` capture helpers.

- [ ] **Step 1: Write the failing test**

Add to `PasteboardManagerTests`-style fake. The existing tests use a fake pasteboard (check the top of `PasteboardMonitorTests.swift` for the existing harness; reuse it). Add:

```swift
func test_emptyPasteboardReadDoesNotBurnChangeCount() throws {
    let pb = FakePasteboard()            // existing test double
    let store = try makeStore()          // existing helper
    let monitor = PasteboardMonitor(pasteboard: pb, store: store,
                                     blobStore: try makeBlobStore())

    monitor.start()
    // App bumped changeCount but data not yet written (transient empty).
    pb.changeCount += 1
    pb.stringValue = nil
    monitor.tickForTesting()
    XCTAssertEqual(try store.recentItems(limit: 10).count, 0)

    // Data arrives on the next poll WITHOUT a further changeCount bump.
    pb.stringValue = "hello"
    monitor.tickForTesting()
    let items = try store.recentItems(limit: 10)
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.body, "hello")
}

func test_persistentlyEmptyChangeCountGivesUpAfterRetryBudget() throws {
    let pb = FakePasteboard()
    let store = try makeStore()
    let monitor = PasteboardMonitor(pasteboard: pb, store: store,
                                    blobStore: try makeBlobStore())
    monitor.start()
    pb.changeCount += 1
    pb.stringValue = nil
    // Budget is 3 empty retries; tick more than that.
    for _ in 0..<6 { monitor.tickForTesting() }
    // Now content appears for the SAME changeCount — already given up, so ignored.
    pb.stringValue = "late"
    monitor.tickForTesting()
    XCTAssertEqual(try store.recentItems(limit: 10).count, 0)
}
```

If `FakePasteboard`, `makeStore`, `makeBlobStore`, `recentItems` differ in the existing file, match the existing names exactly — read the current test file first and adapt the doubles, not the intent.

- [ ] **Step 2: Run to verify it fails**

Run: `make test 2>&1 | grep -A3 PasteboardMonitorTests`
Expected: FAIL (first ⌘C lost — second test asserts current-broken behavior already, first test fails because count==0 after content arrives).

- [ ] **Step 3: Implement**

In `PasteboardMonitor.swift`:

```swift
private enum RouteOutcome { case handled, empty }

static let maxEmptyRetries = 3
private var pendingChangeCount: Int = -1
private var pendingAttempts: Int = 0
```

Replace `tick()`:

```swift
private func tick() {
    let current = pasteboard.changeCount
    guard current != lastChangeCount else { return }
    guard Date() >= pausedUntil else {
        Log.app.debug("monitor paused, skipping change")
        lastChangeCount = current
        return
    }
    // Track retry budget per change count.
    if current != pendingChangeCount {
        pendingChangeCount = current
        pendingAttempts = 0
    }
    pendingAttempts += 1

    switch route() {
    case .handled:
        lastChangeCount = current
    case .empty:
        if pendingAttempts >= Self.maxEmptyRetries {
            // Genuinely empty / unreadable — give up, don't reprocess forever.
            lastChangeCount = current
        }
        // else: leave lastChangeCount unchanged so the next poll re-reads.
    }
}
```

Change `route()` to return `RouteOutcome`:
- The concealed-type skip, strict-capture skip, and excluded-bundle outcomes all `return .handled`.
- File URL capture, image capture, text record (when text non-empty) → `return .handled`.
- Falling through with no recognized content → `return .empty`.

Concretely, make the file/image/text branches return `.handled` after their capture call, and add a final `return .empty` at the end. The concealed-type and strict-capture early returns become `return .handled`. (Image/file capture helpers can stay `Void`; route returns `.handled` after calling them.)

- [ ] **Step 4: Run to verify pass**

Run: `make test 2>&1 | grep -A3 PasteboardMonitorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Services/PasteboardMonitor.swift ClipboardManagerTests/PasteboardMonitorTests.swift
git commit -m "fix: monitor retries transient empty pasteboard reads instead of burning the change count

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Part 2 — Bug: image previews not showing (debug-driven)

### Task 2: Diagnose the live install

**Files:** none yet (investigation).

- [ ] **Step 1: Count image rows in the live DB**

Run:
```bash
sqlite3 ~/Library/"Application Support/Clipboard Manager/clipboard.sqlite" \
  "SELECT kind, COUNT(*) FROM items WHERE deletedAt IS NULL GROUP BY kind;"
```
Record whether `image` rows exist. If zero → the bug is in capture (Part 1 area or `captureImage`); investigate why. If non-zero → continue.

- [ ] **Step 2: Confirm blob files exist**

Run:
```bash
sqlite3 ~/Library/"Application Support/Clipboard Manager/clipboard.sqlite" \
  "SELECT id, blobPath, dimensions FROM items WHERE kind='image' AND deletedAt IS NULL LIMIT 5;"
ls -la ~/Library/"Application Support/Clipboard Manager"/blobs 2>/dev/null || \
  find ~/Library/"Application Support/Clipboard Manager" -name '*.png' 2>/dev/null | head
```
Confirm each `blobPath` maps to a file on disk. (Confirm the blob root path by reading `BlobStore` init in `AppCoordinator`.)

- [ ] **Step 3: Confirm decode path in a test harness**

The card renders via `ImageCache.shared.image(forKey:blobStore:path:)` → `blobStore.read` → `NSImage(data:)`. Write a throwaway test (or use the existing `ImageCacheTests` / `BlobStoreTests` harness) that: writes a known PNG through `BlobStore.write`, reads it back via `BlobStore.read`, and asserts `NSImage(data:)` is non-nil. This isolates whether the blob round-trip or the decode is at fault.

- [ ] **Step 4: Verify `decrypt()` preserves `blobPath`**

Confirm (read `ClipboardStore.decrypt` at `ClipboardStore.swift:573`): it copies `body`/`sourceApp`/`sourceBundleId` and leaves `blobPath` (plaintext column) intact. If a recorded image `Item` returned to the UI has a nil/wrong `blobPath`, that's the root cause. Add a round-trip test: `recordImage(...)` then fetch the item back via the store's normal query path and assert `blobPath` is non-nil and matches.

**Stop and report findings before Task 3.** Task 3's content is determined by what Task 2 finds; do not pre-write the fix.

### Task 3: Failing regression test + fix at the identified layer

**Files:** (determined by Task 2 — likely one of)
- Modify: `ClipboardManager/UI/ImageCache.swift`, or `ClipboardManager/Services/PasteboardMonitor.swift` (captureImage), or `ClipboardManager/Store/ClipboardStore.swift`
- Test: the matching `*Tests.swift`

- [ ] **Step 1: Write a failing test reproducing the confirmed root cause**

Encode the exact failure found in Task 2 as an assertion at the layer it lives in (capture → `recordImage` produces a readable blob; or store → fetched item keeps `blobPath`; or cache → known blob decodes). Use the existing test harness for that layer.

- [ ] **Step 2: Run to verify it fails**

Run: `make test 2>&1 | tail -20`
Expected: FAIL with the assertion matching the diagnosed cause.

- [ ] **Step 3: Implement the minimal fix**

Apply the change indicated by the evidence. (Example shapes — pick the one matching findings: if `NSImage(data:)` returns nil for valid PNG bytes, switch `ImageCache` to `NSImage(data:)` via `NSBitmapImageRep`/`CGImageSource`; if `blobPath` is dropped, fix the fetch path; if capture never wrote the blob, fix `captureImage`.)

- [ ] **Step 4: Run to verify pass**

Run: `make test 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix: image previews render in drawer (<root cause from Task 2>)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Part 3 — Feature: annotate images

### Task 4: `ImageAnnotation` model + `ImageAnnotator.flatten`

**Files:**
- Create: `ClipboardManager/ActionsKit/ImageAnnotator.swift`
- Test: `ClipboardManagerTests/ImageAnnotatorTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum AnnotationTool: String, CaseIterable, Identifiable { case pen, arrow, rectangle, text; var id: String { rawValue } }

  struct Annotation: Identifiable, Equatable {
      let id: UUID
      var tool: AnnotationTool
      var points: [CGPoint]      // pen: path; arrow/rect: [start, end]
      var text: String           // text tool only
      var colorHex: String       // e.g. "#FF3B30"
      var lineWidth: CGFloat
  }

  enum ImageAnnotator {
      /// Composites `annotations` over `base` and returns PNG bytes.
      /// Coordinates in `annotations` are in the base image's pixel space.
      static func flatten(base: NSImage, annotations: [Annotation]) throws -> Data
      enum Failure: Error { case noBitmap, encodeFailed }
  }
  ```
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import AppKit
@testable import ClipboardManager

final class ImageAnnotatorTests: XCTestCase {
    private func solidImage(_ size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        img.unlockFocus()
        return img
    }

    func test_flattenReturnsPNGOfSamePixelSize() throws {
        let base = solidImage(NSSize(width: 100, height: 80))
        let ann = Annotation(id: UUID(), tool: .rectangle,
                             points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 50)],
                             text: "", colorHex: "#FF0000", lineWidth: 4)
        let data = try ImageAnnotator.flatten(base: base, annotations: [ann])
        let out = try XCTUnwrap(NSImage(data: data))
        let rep = try XCTUnwrap(out.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep.pixelsWide, 100)
        XCTAssertEqual(rep.pixelsHigh, 80)
        XCTAssertFalse(data.isEmpty)
    }

    func test_flattenWithAnnotationDiffersFromBlank() throws {
        let base = solidImage(NSSize(width: 50, height: 50))
        let blank = try ImageAnnotator.flatten(base: base, annotations: [])
        let pen = Annotation(id: UUID(), tool: .pen,
                             points: [CGPoint(x: 5, y: 5), CGPoint(x: 45, y: 45)],
                             text: "", colorHex: "#000000", lineWidth: 6)
        let drawn = try ImageAnnotator.flatten(base: base, annotations: [pen])
        XCTAssertNotEqual(blank, drawn)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `make test 2>&1 | grep -A3 ImageAnnotatorTests`
Expected: FAIL ("cannot find 'ImageAnnotator'").

- [ ] **Step 3: Implement**

Create `ImageAnnotator.swift`. `flatten` draws the base into an `NSBitmapImageRep` sized to the base's pixel dimensions, then strokes each annotation:
- pen → `NSBezierPath` connecting `points`.
- arrow → line from `points[0]` to `points[1]` plus a two-stroke arrowhead.
- rectangle → `NSBezierPath(rect:)` between the two points.
- text → `NSAttributedString` drawn at `points[0]` with `colorHex` color, font size scaled to `lineWidth*4`.

Use a `colorFromHex(_:) -> NSColor` private helper. Encode the rep to PNG via `rep.representation(using: .png, properties: [:])`; throw `Failure.encodeFailed` if nil. Get the base bitmap via `base.representations.first as? NSBitmapImageRep` else draw the image into a fresh rep; throw `Failure.noBitmap` if size is zero.

- [ ] **Step 4: Run to verify pass**

Run: `make test 2>&1 | grep -A3 ImageAnnotatorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/ActionsKit/ImageAnnotator.swift ClipboardManagerTests/ImageAnnotatorTests.swift
git commit -m "feat: ImageAnnotator core — annotation model + PNG flatten

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 5: `annotationSaveFolder` setting + folder bookmark helper

**Files:**
- Modify: `ClipboardManager/Settings.swift`
- Create: `ClipboardManager/Services/AnnotationFolder.swift`
- Test: `ClipboardManagerTests/AnnotationFolderTests.swift`

**Interfaces:**
- Produces:
  ```swift
  // Settings.Key.annotationSaveFolder = "annotationSaveFolder"  (Data? bookmark)
  extension Settings { var annotationSaveBookmark: Data? { get nonmutating set } }

  enum AnnotationFolder {
      /// Resolves the saved security-scoped bookmark to a URL, or returns
      /// ~/Pictures when unset/stale. `.bool` out-param reports staleness.
      static func resolve(bookmark: Data?) -> URL
      /// Writes `png` as annotated-<timestamp>.png into `folder`; returns the URL.
      static func write(png: Data, to folder: URL, timestamp: Int64) throws -> URL
      static func makeBookmark(for url: URL) throws -> Data
  }
  ```
- Consumes: nothing.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClipboardManager

final class AnnotationFolderTests: XCTestCase {
    func test_resolveNilBookmarkFallsBackToPictures() {
        let url = AnnotationFolder.resolve(bookmark: nil)
        XCTAssertTrue(url.path.contains("Pictures"))
    }

    func test_writeProducesTimestampedPNG() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let out = try AnnotationFolder.write(png: Data([0x89, 0x50]), to: tmp, timestamp: 1718000000)
        XCTAssertTrue(out.lastPathComponent.hasPrefix("annotated-"))
        XCTAssertTrue(out.lastPathComponent.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    }

    func test_roundTripBookmark() throws {
        let tmp = FileManager.default.temporaryDirectory
        let data = try AnnotationFolder.makeBookmark(for: tmp)
        let resolved = AnnotationFolder.resolve(bookmark: data)
        XCTAssertEqual(resolved.standardizedFileURL.path, tmp.standardizedFileURL.path)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `make test 2>&1 | grep -A3 AnnotationFolderTests`
Expected: FAIL ("cannot find 'AnnotationFolder'").

- [ ] **Step 3: Implement**

Add to `Settings.Key`: `static let annotationSaveFolder = "annotationSaveFolder"`. Add computed `annotationSaveBookmark: Data?` (get `defaults.data(forKey:)`, set `defaults.set(_, forKey:)`).

Create `AnnotationFolder.swift`:
- `resolve`: if bookmark nil → `FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)`. Else `URL(resolvingBookmarkData:options:.withSecurityScope,...)`, falling back to Pictures on error.
- `makeBookmark`: `url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)`.
- `write`: `let name = "annotated-\(timestamp).png"`; `let dest = folder.appendingPathComponent(name)`; `try png.write(to: dest)`; return `dest`. (Caller wraps with `startAccessingSecurityScopedResource()` when using a resolved bookmark.)

- [ ] **Step 4: Run to verify pass**

Run: `make test 2>&1 | grep -A3 AnnotationFolderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Settings.swift ClipboardManager/Services/AnnotationFolder.swift ClipboardManagerTests/AnnotationFolderTests.swift
git commit -m "feat: annotationSaveFolder setting + bookmark/write helper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 6: Settings UI row for the save folder

**Files:**
- Modify: `ClipboardManager/UI/Preferences/GeneralPane.swift`

**Interfaces:**
- Consumes: `Settings.Key.annotationSaveFolder`, `AnnotationFolder.makeBookmark`, `AnnotationFolder.resolve`.

- [ ] **Step 1: Implement (UI — verified by build + manual check, no unit test)**

Add `@AppStorage(Settings.Key.annotationSaveFolder) private var annotationFolderData: Data?`. Add a Section:

```swift
Section("Annotation") {
    HStack {
        Text("Save folder")
        Spacer()
        Text(AnnotationFolder.resolve(bookmark: annotationFolderData)
                .lastPathComponent)
            .foregroundStyle(.secondary)
        Button("Choose…") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url,
               let data = try? AnnotationFolder.makeBookmark(for: url) {
                annotationFolderData = data
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `make build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Preferences/GeneralPane.swift
git commit -m "feat: Settings row to pick the annotation save folder

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 7: `AnnotationCanvas` + `ImageAnnotationView` editor

**Files:**
- Create: `ClipboardManager/UI/Annotation/ImageAnnotationView.swift` (contains `AnnotationCanvas` + `ImageAnnotationView`)
- Test: none (SwiftUI view — verified by build; logic lives in `ImageAnnotator`, already tested)

**Interfaces:**
- Produces:
  ```swift
  struct ImageAnnotationView: View {
      let base: NSImage
      var onCopy: (Data) -> Void          // flattened PNG
      var onSaveToFolder: (Data) -> Void
      var onSaveToHistory: (Data) -> Void
      var onClose: () -> Void
  }
  ```
- Consumes: `ImageAnnotator`, `Annotation`, `AnnotationTool` (Task 4).

- [ ] **Step 1: Implement**

`ImageAnnotationView` holds `@State var annotations: [Annotation]`, `@State var tool: AnnotationTool = .pen`, `@State var colorHex = "#FF3B30"`, `@State var lineWidth: CGFloat = 4`, `@State var draft: Annotation?`.

Toolbar: `Picker` over `AnnotationTool.allCases`, a `ColorPicker` (bind via hex<->Color helper), a thickness `Slider` (1...20), an "Undo" button (`annotations.removeLast()` guarded), and three trailing buttons:
- "Copy" → `flattenThenCallback(onCopy)`
- "Save to Folder" → `flattenThenCallback(onSaveToFolder)`
- "Save to History" → `flattenThenCallback(onSaveToHistory)`

`flattenThenCallback` calls `try? ImageAnnotator.flatten(base: base, annotations: annotations)`, then the callback, then `onClose()`.

`AnnotationCanvas` renders `Image(nsImage: base).resizable().aspectRatio(contentMode: .fit)` in a `GeometryReader`, overlays a `Canvas` that draws committed `annotations` + `draft`, and a `DragGesture` that, for pen, appends points to `draft.points`; for arrow/rectangle sets `draft.points = [start, current]`; on end appends `draft` to `annotations`. For `.text`, a tap presents a `TextField` alert/popover capturing the string into a new text annotation at the tap point. **Convert view coordinates to base pixel space** (multiply by `base.size.width / viewWidth`) before storing, so flatten coordinates match.

- [ ] **Step 2: Build**

Run: `make build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Annotation/ImageAnnotationView.swift
git commit -m "feat: image annotation editor view (canvas + tools + outputs)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 8: Wire "Annotate" action through the card → drawer → coordinator

**Files:**
- Modify: `ClipboardManager/UI/Drawer/ClipboardCard.swift` (add `onAnnotate` + menu item)
- Modify: `ClipboardManager/UI/Drawer/DrawerView.swift` (thread `onAnnotate` callback)
- Modify: `ClipboardManager/App/AppCoordinator.swift` (present the editor window + handle the three outputs)

**Interfaces:**
- Consumes: `ImageAnnotationView` (Task 7), `ImageCache` (decode the item's blob to `NSImage`), `ImageAnnotator`, `AnnotationFolder`, `ClipboardStore.recordImage`, `BlobStore`, `ImageProcessor`.
- Produces: `ClipboardCard.onAnnotate: ((Item) -> Void)?`; the coordinator gains `func presentAnnotation(for item: Item)`.

- [ ] **Step 1: Add `onAnnotate` to the card + menu item**

In `ClipboardCard.swift`: add `var onAnnotate: ((Item) -> Void)? = nil`. In `contextMenu`, inside the existing image branch area, add (only for images):

```swift
if item.kind == "image" {
    Button("Annotate") { onAnnotate?(item) }
}
```

- [ ] **Step 2: Thread through `DrawerView`**

In `DrawerView.swift`: add `var onAnnotate: ((Item) -> Void)? = nil` next to the other callbacks (line ~9-11), and pass `onAnnotate: { onAnnotate?($0) }` into the `ClipboardCard(...)` initializer (line ~145-150).

- [ ] **Step 3: Implement `presentAnnotation` in the coordinator + pass the callback when building the drawer**

In `AppCoordinator.swift`, add:

```swift
@MainActor
func presentAnnotation(for item: Item) {
    guard let path = item.blobPath,
          let nsImage = ImageCache.shared.image(forKey: path, blobStore: blobStore, path: path)
    else { Log.coordinator.error("annotate: cannot load image blob"); return }

    let view = ImageAnnotationView(
        base: nsImage,
        onCopy: { png in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
        },
        onSaveToFolder: { [settings] png in
            let folder = AnnotationFolder.resolve(bookmark: settings.annotationSaveBookmark)
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            do { _ = try AnnotationFolder.write(png: png, to: folder,
                                                timestamp: Int64(Date().timeIntervalSince1970)) }
            catch { Log.coordinator.error("annotate save failed: \(error.localizedDescription, privacy: .public)") }
        },
        onSaveToHistory: { [store, blobStore] png in
            do {
                let processed = try ImageProcessor.process(data: png)
                let blobPath = try blobStore.write(data: processed.thumbnailData, fileExtension: "png")
                let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                let recorded = try store.recordImage(contentHash: hash, blobPath: blobPath,
                    dimensions: processed.pixelSize, byteSize: png.count,
                    sourceApp: "Annotation", sourceBundleId: nil)
                if recorded == nil || (recorded!.blobPath != nil && recorded!.blobPath != blobPath) {
                    try? blobStore.delete(relativePath: blobPath)
                }
            } catch { Log.coordinator.error("annotate history save failed: \(error.localizedDescription, privacy: .public)") }
        },
        onClose: { [weak self] in self?.annotationWindow?.close(); self?.annotationWindow = nil }
    )
    let hosting = NSHostingController(rootView: view)
    let window = NSWindow(contentViewController: hosting)
    window.title = "Annotate Image"
    window.styleMask = [.titled, .closable, .resizable]
    window.setContentSize(NSSize(width: 720, height: 560))
    window.center()
    let wc = NSWindowController(window: window)
    wc.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    annotationWindow = window
}
```

Add stored prop `private var annotationWindow: NSWindow?`. Add `import CryptoKit` and `import SwiftUI` to the file if not already present. Confirm `store` and `blobStore` are accessible properties on the coordinator (they are — used in init); if they're `let` locals, promote to stored properties.

Where the coordinator builds the `DrawerView` (find the existing `DrawerView(` construction — likely in `DrawerWindow`/drawer setup), pass `onAnnotate: { [weak self] item in self?.presentAnnotation(for: item) }`. If the drawer is built in a window controller rather than the coordinator, route the callback to call back into the coordinator's `presentAnnotation`.

- [ ] **Step 4: Build**

Run: `make build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run full test suite**

Run: `make test 2>&1 | tail -15`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: wire Annotate action from image card to editor with copy/save/history outputs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 9: Manual verification

- [ ] Build + install the team-signed Release build (ad-hoc rebuilds invalidate Accessibility TCC — see project memory). Run `make run`.
- [ ] Copy text quickly once (single ⌘C) from several apps; confirm it appears in the drawer on the first copy.
- [ ] Confirm image items show thumbnails in the drawer.
- [ ] Right-click an image card → Annotate; draw with each tool; Copy → paste elsewhere; Save to Folder → confirm PNG in the chosen folder; Save to History → confirm a new image item.

---

## Self-Review Notes

- **Spec coverage:** Part 1 → Task 1. Part 2 → Tasks 2–3 (debug-driven, as specified). Part 3: model/flatten → Task 4; setting + folder helper → Task 5; settings UI → Task 6; editor → Task 7; entry-point wiring + three outputs → Task 8; manual verify → Task 9. All four tools and all three outputs covered.
- **Type consistency:** `Annotation`/`AnnotationTool`/`ImageAnnotator.flatten` defined in Task 4 and consumed unchanged in Tasks 7–8. `AnnotationFolder.resolve/write/makeBookmark` and `Settings.annotationSaveBookmark` defined in Task 5, consumed in Tasks 6 + 8. `onAnnotate` added in Task 8 across card/drawer.
- **Known adaptation point:** Task 1's test doubles (`FakePasteboard`, `makeStore`, `recentItems`) must match the names already in `PasteboardMonitorTests.swift` — read it first. Task 8's drawer-construction site must be located (coordinator vs window controller) before wiring the callback.
