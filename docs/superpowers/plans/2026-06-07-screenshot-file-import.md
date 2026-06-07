# Screenshot File Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture macOS screenshots that are saved as files to disk (⌘⇧4, default behavior) into LimiClip's clipboard history, since those never touch the clipboard and are currently invisible to the app.

**Architecture:** A new `@MainActor` service, `ScreenshotImporter`, watches the user's screenshot save folder (read from `com.apple.screencapture` defaults, default `~/Desktop`) via an `NSMetadataQuery` filtered to `kMDItemIsScreenCapture == 1`. New screenshot files are read, downsampled through the existing `ImageProcessor`, written to `BlobStore`, and recorded with `ClipboardStore.recordImage` — reusing the entire existing image pipeline (thumbnailing, encryption, dedup, 5-image cap). A new `Settings.captureScreenshotFiles` flag (default **on**) gates the service, with a toggle in the Privacy preferences pane. The import core (`importFile(at:)`) is factored out for unit testing; the metadata-query wiring is verified by running the app.

**Tech Stack:** Swift, AppKit, `NSMetadataQuery` (Spotlight), CoreGraphics/ImageIO (existing `ImageProcessor`), GRDB-backed `ClipboardStore`, XCTest.

---

## Root Cause (why this plan exists)

Confirmed by live reproduction on 2026-06-07:
- `com.apple.screencapture location` = Desktop, `target` = file → ⌘⇧4 screenshots are written as `Screenshot ….png` files and **nothing is placed on the clipboard**.
- LimiClip's `PasteboardMonitor` only watches `NSPasteboard`, so it never sees file-based screenshots.
- Raw clipboard image data (right-click → "Copy Image", ⌘⌃⇧4) IS captured correctly — verified `recordImage` path works end to end.

This feature adds a second capture source (the screenshot folder) alongside the existing clipboard monitor.

## File Structure

- **Create:** `ClipboardManager/Services/ScreenshotImporter.swift` — the watcher service + testable `importFile(at:)` core + screenshot-folder resolver.
- **Create:** `ClipboardManagerTests/ScreenshotImporterTests.swift` — unit tests for `importFile(at:)` and the folder resolver.
- **Modify:** `ClipboardManager/Settings.swift` — add `Key.captureScreenshotFiles` and the `captureScreenshotFiles` computed property (default `true`).
- **Modify:** `ClipboardManagerTests/SettingsTests.swift` — test the new default + round-trip.
- **Modify:** `ClipboardManager/UI/Preferences/PrivacyPane.swift` — add the "Capture screenshots saved to disk" toggle.
- **Modify:** `ClipboardManager/App/AppCoordinator.swift` — construct, start, and stop the importer; restart on settings change.

## Key design decisions

- **Detection by Spotlight attribute, not filename.** `kMDItemIsScreenCapture == 1` is locale-independent and set by macOS only on real screenshots, so we never import arbitrary Desktop files. This is the privacy guardrail that makes "on by default" acceptable.
- **Baseline on launch.** When the query finishes its initial gather, record existing screenshot paths into a `seen` set and do NOT import them — only screenshots that appear *after* the app starts are imported. This avoids dumping the user's entire Desktop backlog into history on first run.
- **Reuse the image pipeline.** `importFile(at:)` calls the same `ImageProcessor.process` → `BlobStore.write` → `ClipboardStore.recordImage` chain as clipboard images, so encryption, dedup (by SHA-256 of original bytes), and the 5-image cap all apply automatically. `sourceApp` is recorded as `"Screenshot"`, `sourceBundleId` as `nil`.
- **Separate from existing `saveScreenshots`.** `saveScreenshots` (default off) governs the in-app ⌘⇧A `screencapture -i -c` clipboard screenshot. The new `captureScreenshotFiles` (default on) governs disk-based macOS screenshots. They are independent and must not be conflated.

## Risk / manual-verification note

Reading files from `~/Desktop` can trigger a macOS TCC "access your Desktop folder" prompt depending on the app's sandbox/hardened-runtime config. Task 5 includes a manual run to confirm the prompt is acceptable and that import works after granting access. If access is denied, `importFile` logs and skips (never crashes).

---

### Task 1: Add the `captureScreenshotFiles` setting

**Files:**
- Modify: `ClipboardManager/Settings.swift:38-47` (Key enum) and after `:113` (properties)
- Test: `ClipboardManagerTests/SettingsTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `ClipboardManagerTests/SettingsTests.swift`:

```swift
func test_captureScreenshotFiles_defaultsOn() {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let settings = Settings(defaults: defaults)
    XCTAssertTrue(settings.captureScreenshotFiles)
}

func test_captureScreenshotFiles_roundTrips() {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let settings = Settings(defaults: defaults)
    settings.captureScreenshotFiles = false
    XCTAssertFalse(settings.captureScreenshotFiles)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS' test -only-testing:ClipboardManagerTests/SettingsTests/test_captureScreenshotFiles_defaultsOn`
Expected: FAIL — `value of type 'Settings' has no member 'captureScreenshotFiles'`.

- [ ] **Step 3: Add the key and property**

In `Settings.swift`, add to the `Key` enum (after `saveScreenshots`):

```swift
        static let captureScreenshotFiles = "captureScreenshotFiles"
```

Add this property after `saveScreenshots` (after line 113):

```swift
    /// When on, macOS screenshots saved as files to the screenshot folder
    /// (⌘⇧4, default behaviour) are imported into clipboard history. Default
    /// on. Independent of `saveScreenshots`, which governs the in-app ⌘⇧A
    /// clipboard screenshot.
    var captureScreenshotFiles: Bool {
        get {
            if defaults.object(forKey: Key.captureScreenshotFiles) == nil { return true }
            return defaults.bool(forKey: Key.captureScreenshotFiles)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.captureScreenshotFiles) }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS' test -only-testing:ClipboardManagerTests/SettingsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Settings.swift ClipboardManagerTests/SettingsTests.swift
git commit -m "feat: add captureScreenshotFiles setting (default on)"
```

---

### Task 2: Screenshot-folder resolver

**Files:**
- Create: `ClipboardManager/Services/ScreenshotImporter.swift`
- Test: `ClipboardManagerTests/ScreenshotImporterTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ClipboardManagerTests/ScreenshotImporterTests.swift`:

```swift
import XCTest
@testable import LimiClip

final class ScreenshotImporterTests: XCTestCase {

    func test_resolveScreenshotFolder_fallsBackToDesktop() {
        // No custom location set → ~/Desktop.
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS' test -only-testing:ClipboardManagerTests/ScreenshotImporterTests/test_resolveScreenshotFolder_fallsBackToDesktop`
Expected: FAIL — `cannot find 'ScreenshotImporter' in scope`.

- [ ] **Step 3: Create the file with the resolver**

Create `ClipboardManager/Services/ScreenshotImporter.swift`:

```swift
// ClipboardManager/Services/ScreenshotImporter.swift
import AppKit
import Foundation
import CryptoKit

/// Imports macOS screenshots that are saved as *files* (the default ⌘⇧4
/// behaviour) into clipboard history. Such screenshots never touch the
/// pasteboard, so `PasteboardMonitor` cannot see them; this service watches
/// the screenshot folder instead and feeds new screenshots through the same
/// image pipeline (`ImageProcessor` → `BlobStore` → `ClipboardStore`).
@MainActor
final class ScreenshotImporter {

    /// Resolves the folder macOS writes screenshots to. `location` is the raw
    /// value of `com.apple.screencapture`'s `location` default (may be nil,
    /// a tilde path, or an absolute path). Falls back to ~/Desktop.
    static func resolveScreenshotFolder(location: String?) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let location, !location.isEmpty else {
            return home.appendingPathComponent("Desktop", isDirectory: true)
        }
        let expanded = (location as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS' test -only-testing:ClipboardManagerTests/ScreenshotImporterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Services/ScreenshotImporter.swift ClipboardManagerTests/ScreenshotImporterTests.swift
git commit -m "feat: add ScreenshotImporter screenshot-folder resolver"
```

---

### Task 3: Importable core — `importFile(at:)`

**Files:**
- Modify: `ClipboardManager/Services/ScreenshotImporter.swift`
- Test: `ClipboardManagerTests/ScreenshotImporterTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `ScreenshotImporterTests.swift`. This mirrors the store/blob setup used in `ClipboardStoreTests` (`testingConfiguration()`) and `BlobStoreTests` (`BlobStore(rootDirectory:)`):

```swift
@MainActor
func test_importFile_recordsImageItem() throws {
    let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    let blobDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("shots-\(UUID().uuidString)", isDirectory: true)
    let blobStore = try BlobStore(rootDirectory: blobDir)
    let importer = ScreenshotImporter(store: store, blobStore: blobStore, settings: { Settings() })

    // Write a real PNG to a temp file (a 2x2 image encoded via ImageIO).
    let pngURL = blobDir.appendingPathComponent("Screenshot.png")
    try Self.writeTestPNG(to: pngURL)

    let item = try importer.importFile(at: pngURL)

    XCTAssertNotNil(item)
    XCTAssertEqual(item?.kind, "image")
    XCTAssertNotNil(item?.blobPath)
    XCTAssertEqual(try store.recentItems(limit: 10).filter { $0.kind == "image" }.count, 1)
}

@MainActor
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

/// Encodes a tiny opaque PNG to `url` using ImageIO.
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
```

Add the imports needed for the helper at the top of the test file:

```swift
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS' test -only-testing:ClipboardManagerTests/ScreenshotImporterTests/test_importFile_recordsImageItem`
Expected: FAIL — no `init(store:blobStore:settings:)` and no `importFile(at:)`.

- [ ] **Step 3: Add the init, stored deps, and `importFile(at:)`**

In `ScreenshotImporter.swift`, add stored properties and methods inside the class (above the static resolver):

```swift
    private let store: ClipboardStore
    private let blobStore: BlobStore
    private let settings: () -> Settings

    init(store: ClipboardStore, blobStore: BlobStore, settings: @escaping () -> Settings = { Settings() }) {
        self.store = store
        self.blobStore = blobStore
        self.settings = settings
    }

    /// Reads a screenshot file, downsamples + re-encodes it via `ImageProcessor`,
    /// writes the (encrypted) thumbnail blob, and records an image row. Dedup,
    /// encryption, and the image cap are handled by `ClipboardStore.recordImage`.
    /// Returns nil if the file can't be read or isn't a decodable image (logged,
    /// never throws on a bad/locked file).
    @discardableResult
    func importFile(at url: URL) throws -> Item? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Log.app.error("screenshot import: cannot read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let processed: ImageProcessor.Result
        do {
            processed = try ImageProcessor.process(data: data)
        } catch {
            Log.app.error("screenshot import: not a decodable image: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        let blobPath = try blobStore.write(data: processed.thumbnailData, fileExtension: "png")
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try store.recordImage(
            contentHash: hash,
            blobPath: blobPath,
            dimensions: processed.pixelSize,
            byteSize: data.count,
            sourceApp: "Screenshot",
            sourceBundleId: nil
        )
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS' test -only-testing:ClipboardManagerTests/ScreenshotImporterTests`
Expected: PASS (all four tests).

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Services/ScreenshotImporter.swift ClipboardManagerTests/ScreenshotImporterTests.swift
git commit -m "feat: ScreenshotImporter.importFile reuses image pipeline with dedup"
```

---

### Task 4: Folder watching with `NSMetadataQuery` + launch baseline

**Files:**
- Modify: `ClipboardManager/Services/ScreenshotImporter.swift`

> No unit test: `NSMetadataQuery` requires Spotlight + a runloop and is verified by the manual run in Task 5. Keep this task limited to wiring so the testable core (Task 3) carries the logic coverage.

- [ ] **Step 1: Add query state + start/stop**

Add to `ScreenshotImporter`:

```swift
    private var query: NSMetadataQuery?
    private var seenPaths: Set<String> = []
    private var hasGathered = false

    func start() {
        guard query == nil else { return }
        guard settings().captureScreenshotFiles else {
            Log.app.info("screenshot import disabled by setting")
            return
        }
        let folder = Self.resolveScreenshotFolder(
            location: CFPreferencesCopyAppValue("location" as CFString,
                                                "com.apple.screencapture" as CFString) as? String
        )
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        q.searchScopes = [folder]
        q.operationQueue = .main

        NotificationCenter.default.addObserver(
            self, selector: #selector(gatheringFinished(_:)),
            name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryUpdated(_:)),
            name: .NSMetadataQueryDidUpdate, object: q)

        q.start()
        query = q
        Log.app.info("screenshot import watching \(folder.path, privacy: .public)")
    }

    func stop() {
        guard let q = query else { return }
        q.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: q)
        query = nil
        hasGathered = false
        seenPaths.removeAll()
    }

    /// Initial gather = the screenshots that already exist when we launch.
    /// Record them as "seen" so we never back-fill the user's Desktop history.
    @objc private func gatheringFinished(_ note: Notification) {
        guard let q = query else { return }
        q.disableUpdates()
        for i in 0..<q.resultCount {
            if let item = q.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                seenPaths.insert(path)
            }
        }
        hasGathered = true
        q.enableUpdates()
    }

    /// A new (or changed) screenshot appeared. Import any path we haven't seen.
    @objc private func queryUpdated(_ note: Notification) {
        guard hasGathered, let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !seenPaths.contains(path) else { continue }
            seenPaths.insert(path)
            do {
                _ = try importFile(at: URL(fileURLWithPath: path))
            } catch {
                Log.app.error("screenshot import failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
```

Add `import Foundation` is already present; ensure the file imports nothing else new (`NSMetadataQuery`, `CFPreferencesCopyAppValue` are in Foundation/CoreFoundation via AppKit).

- [ ] **Step 2: Build to verify it compiles**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/Services/ScreenshotImporter.swift
git commit -m "feat: ScreenshotImporter watches screenshot folder via NSMetadataQuery"
```

---

### Task 5: Wire into AppCoordinator + Privacy toggle

**Files:**
- Modify: `ClipboardManager/App/AppCoordinator.swift:13-62` (add property + construct), `:64-76` (start), `:78-82` (deinit)
- Modify: `ClipboardManager/UI/Preferences/PrivacyPane.swift:8` and `:11-20`

- [ ] **Step 1: Add the importer to AppCoordinator**

In `AppCoordinator.swift`, add a stored property after `private let monitor: PasteboardMonitor` (line 13):

```swift
    private let screenshotImporter: ScreenshotImporter
```

In `init()`, after the `monitor` is created (after line 46), add:

```swift
        self.screenshotImporter = ScreenshotImporter(store: store, blobStore: blobStore)
```

In `start()`, after `monitor.start()` (line 68), add:

```swift
        screenshotImporter.start()
```

Extend the existing `UserDefaults.didChangeNotification` observer in `start()` so toggling the setting starts/stops the importer. Replace the observer body (lines 72-75) with:

```swift
        appearanceObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.applyAppearance()
                self?.applyScreenshotCaptureSetting()
            }
        }
```

Add this helper method to `AppCoordinator` (after `applyAppearance()`, around line 89):

```swift
    private func applyScreenshotCaptureSetting() {
        if Settings().captureScreenshotFiles {
            screenshotImporter.start()   // no-op if already running
        } else {
            screenshotImporter.stop()
        }
    }
```

In `deinit`, add (after the observer removal, around line 81):

```swift
        // screenshotImporter.stop() is MainActor-isolated; deinit cannot call
        // it directly. The NSMetadataQuery is released with the importer, which
        // stops it. No manual stop needed on teardown.
```

- [ ] **Step 2: Add the Privacy toggle**

In `PrivacyPane.swift`, add an `@AppStorage` after line 8:

```swift
    @AppStorage(Settings.Key.captureScreenshotFiles) private var captureScreenshotFiles: Bool = true
```

Add a new `Section` as the first child of the `Form` (before the existing strict-capture Section at line 12):

```swift
            Section {
                Toggle(isOn: $captureScreenshotFiles) {
                    Text("Capture screenshots saved to disk")
                }
            } footer: {
                Text("When on, screenshots macOS saves as files (⌘⇧4) are added to your history. Only items macOS tags as screenshots are imported — other files in the folder are ignored.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 3: Build**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification (the real proof)**

```bash
# Launch the freshly built app
open "$(xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $3; exit}')/LimiClip.app"
```

Then, by hand:
1. Note current image count:
   `sqlite3 "$HOME/Library/Application Support/Clipboard Manager/clipboard.sqlite" "SELECT COUNT(*) FROM items WHERE kind='image';"`
2. Take a screenshot the **default** way: **⌘⇧4**, select a region (it saves to Desktop). Grant the Desktop-access prompt if macOS shows one.
3. Wait ~2-3s, then re-check the count — it should have increased by 1.
4. Open LimiClip (⌘⇧V or the menu bar icon) → the screenshot appears in both the **Images** tab and the **All** tab with a thumbnail.
5. Toggle **Preferences → Privacy → "Capture screenshots saved to disk"** OFF, take another ⌘⇧4 screenshot → count does NOT increase.

Expected: steps 3-4 show the screenshot imported; step 5 shows the toggle gates it.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/App/AppCoordinator.swift ClipboardManager/UI/Preferences/PrivacyPane.swift
git commit -m "feat: wire ScreenshotImporter into app + Privacy toggle"
```

---

## Self-Review

**Spec coverage:**
- Watch screenshot folder → Task 4 (`NSMetadataQuery`, scope = resolved folder). ✓
- Detect screenshots only (not arbitrary files) → Task 4 predicate `kMDItemIsScreenCapture == 1`. ✓
- Reuse ImageProcessor → blob → recordImage → Task 3. ✓
- Honors dedup + 5-image cap + encryption → inherited from `recordImage` (Task 3 test asserts dedup). ✓
- Toggle, on by default → Task 1 (default true) + Task 5 (UI). ✓
- Don't back-fill old screenshots → Task 4 launch baseline (`gatheringFinished`). ✓
- Appears in Images + All tabs → manual verification Task 5 step 4 (kind="image" feeds both). ✓

**Placeholder scan:** No TBD/TODO; all code blocks complete; error handling shown explicitly in `importFile`. ✓

**Type consistency:** `ScreenshotImporter(store:blobStore:settings:)`, `importFile(at:) -> Item?`, `start()`, `stop()`, `resolveScreenshotFolder(location:)`, `Settings.captureScreenshotFiles` / `Key.captureScreenshotFiles` — names used identically across Tasks 1-5. `recordImage` signature matches the existing `ClipboardStore.recordImage(contentHash:blobPath:dimensions:byteSize:sourceApp:sourceBundleId:)`. ✓

## Open follow-ups (out of scope, note for later)

- Live-watching the screenshot *location* default changing mid-session (currently read once at `start()`; toggling the setting re-reads it). 
- Optional: also route image-typed file URLs copied from Finder to image capture (the earlier-discovered "file URLs win" behavior) — separate, smaller change.
