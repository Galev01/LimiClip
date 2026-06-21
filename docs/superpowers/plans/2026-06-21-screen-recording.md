# Screen Recording Implementation Plan

> Execute task-by-task. Each task is TDD where a unit test is feasible, ends with `make test` green (or `make build` for UI-only), and a commit. Tasks are SEQUENTIAL — later tasks consume earlier types and share the `cycle1-stability` branch.

**Goal:** Record the screen (region or full) to a user-chosen folder and surface each recording as a playable video card in the drawer.

**Tech:** Swift 6, AppKit + SwiftUI, GRDB, AVFoundation, `/usr/sbin/screencapture` CLI, XCTest via `make test` (xcodebuild). Spec: `docs/superpowers/specs/2026-06-21-screen-recording-design.md`.

## Global Constraints
- `make test` runs the whole suite (xcodebuild); run after each step. UI-only tasks: `make build`.
- Bump nothing in project.yml here (version bump happens at release).
- Follow existing patterns; READ the analogous file before writing. Key analogues: `Services/ScreenCapturer.swift`, `Services/AnnotationFolder.swift`, `ActionsKit/ImageProcessor.swift`, `Store/FileReference.swift`, `Store/ClipboardStore.swift` (recordImage/recordFile/softDelete), `UI/Drawer/ClipboardCard.swift` (image + file branches), `UI/Annotation/ScreenFreezeOverlay.swift` (SelectionOverlayNSView, ScreenFreezeWindow panel), `UI/MenuBar/MenuBarController.swift`, `Services/HotkeyService.swift`, `UI/Preferences/{GeneralPane,ShortcutsPane}.swift`.
- Encryption: bodies/sourceApp sealed via `cipher`; `blobPath` plaintext column; blob bytes encrypted by BlobStore.
- Swift 6 concurrency: pure helpers callable from tests must be `nonisolated`; cross-actor returns must be Sendable (return `Data`/value types, build `NSImage` on main).
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

### Task 1: `ScreenRecorder` + pure args builder (empirically verify flags)
**Files:** Create `ClipboardManager/Services/ScreenRecorder.swift`; Test `ClipboardManagerTests/ScreenRecorderTests.swift`.

**Interfaces (produce):**
```swift
@MainActor final class ScreenRecorder {
    private var task: Process?
    var isRecording: Bool { get }
    /// Launches `screencapture` video recording of `globalRect` to `outputURL`.
    /// Returns false if launch fails. `onFinish` is called on the main actor
    /// with the output URL once the process exits (file finalized), or nil on failure.
    func start(globalRect: CGRect, audio: Bool, outputURL: URL, onFinish: @escaping @MainActor (URL?) -> Void) -> Bool
    /// Interrupts the recording process; finalization triggers `onFinish`.
    func stop()
    /// PURE, nonisolated: the screencapture argument vector.
    nonisolated static func arguments(globalRect: CGRect, audio: Bool, outputPath: String) -> [String]
}
```
- `arguments`: `["-v"] + (audio ? ["-g"] : []) + ["-R\(Int x),\(Int y),\(Int w),\(Int h)", outputPath]`. (Adjust ONLY if step-2 empirical check proves a different flag set is required for region video; if so, update both code and the test to the verified set.)
- `start`: build Process for `/usr/sbin/screencapture` with the args; set `terminationHandler` to read existence of outputURL and call `onFinish` on main (DispatchQueue.main.async); store task; `try task.run()`. Return false on throw.
- `stop`: `task?.interrupt()` (SIGINT → screencapture finalizes the mov); clear task in onFinish.

**Steps:**
- [ ] Write failing test: `test_argumentsRegionNoAudio` asserts `ScreenRecorder.arguments(globalRect: CGRect(x:10,y:20,width:300,height:200), audio:false, outputPath:"/tmp/x.mov")` equals `["-v","-R10,20,300,200","/tmp/x.mov"]`; `test_argumentsWithAudioIncludesG` asserts `-g` present when audio true.
- [ ] Run `make test` → FAIL (no ScreenRecorder).
- [ ] **Empirically verify flags BEFORE finalizing:** from a shell, run `screencapture -v -V1 -R0,0,200,200 /tmp/limiclip-rectest.mov` then `mdls -name kMDItemDurationSeconds -name kMDItemKind /tmp/limiclip-rectest.mov` (and `ls -la`) to confirm a valid, non-empty `.mov` with a duration was produced. If region video isn't supported by `-v -R`, find the working invocation and set `arguments` (and the test) to it. Record the verified command in a code comment.
- [ ] Implement `ScreenRecorder.swift` with the verified args.
- [ ] Run `make test` → PASS.
- [ ] Commit.

---

### Task 2: `RecordingFolder` + settings + GeneralPane UI
**Files:** Create `ClipboardManager/Services/RecordingFolder.swift`; Modify `ClipboardManager/Settings.swift`, `ClipboardManager/UI/Preferences/GeneralPane.swift`; Test `ClipboardManagerTests/RecordingFolderTests.swift`.

**Interfaces (produce):**
```swift
// Settings.Key.recordingSaveFolder = "recordingSaveFolder" (Data? bookmark)
// Settings.Key.recordAudio = "recordAudio" (Bool, default false)
extension Settings { var recordingSaveBookmark: Data? { get nonmutating set }; var recordAudio: Bool { get nonmutating set } }
enum RecordingFolder {
    static func resolve(bookmark: Data?) -> URL            // ~/Movies fallback
    static func makeBookmark(for url: URL) throws -> Data
    /// Moves `tempFile` into `folder` as recording-<timestamp>.mov; returns final URL.
    static func moveIntoFolder(_ tempFile: URL, folder: URL, timestamp: Int64) throws -> URL
}
```
Mirror `AnnotationFolder` exactly (security-scoped resolve, fallback). `recordAudio` getter: default false when unset (mirror `saveScreenshots`).

**Steps:**
- [ ] Failing tests (mirror `AnnotationFolderTests`): `test_resolveNilBookmarkFallsBackToMovies` (path contains "Movies"); `test_moveIntoFolderProducesTimestampedMov` (write a temp file, move it, assert dest exists, prefix "recording-", suffix ".mov", and the temp no longer exists); `test_roundTripBookmark`.
- [ ] `make test` → FAIL.
- [ ] Implement `RecordingFolder` + Settings keys/properties.
- [ ] Add GeneralPane "Recording" section: `@AppStorage(Settings.Key.recordingSaveFolder) recordingFolderData: Data?`, `@AppStorage(Settings.Key.recordAudio) recordAudio: Bool = false`; a "Save folder" row with `RecordingFolder.resolve(...).lastPathComponent` + "Choose…" NSOpenPanel (canChooseDirectories) → `RecordingFolder.makeBookmark`; a Toggle "Record microphone audio".
- [ ] `make test` → PASS; `make build` → SUCCEEDED.
- [ ] Commit.

---

### Task 3: `VideoReference` + `ItemKind.video` + `recordVideo` + `VideoThumbnail`
**Files:** Create `ClipboardManager/Store/VideoReference.swift`, `ClipboardManager/ActionsKit/VideoThumbnail.swift`; Modify `ClipboardManager/Store/ItemKind.swift`, `ClipboardManager/Store/ClipboardStore.swift`; Tests `ClipboardManagerTests/VideoReferenceTests.swift`, `ClipboardManagerTests/RecordVideoTests.swift`.

**Interfaces (produce):**
```swift
struct VideoReference: Codable, Equatable, Sendable {
    let path: String; let name: String; let byteSize: Int64; let modifiedAt: Int64
    let durationSeconds: Double; let width: Int; let height: Int
    var formattedSize: String; var formattedDuration: String   // "1:05"
    func encodedJSON() throws -> String
    static func decodingJSON(_ raw: String) throws -> VideoReference
}
// ItemKind gains `case video` → kindColumn "video", subtypeColumn nil, from("video",_) → .video
extension ClipboardStore {
    @discardableResult
    func recordVideo(reference: VideoReference, thumbnailBlobPath: String?, sourceApp: String?) throws -> Item?
}
enum VideoThumbnail {
    /// First-frame PNG (≤maxPixel via ImageProcessor) + pixel size + duration. nil if unreadable.
    static func firstFrame(url: URL, maxPixel: CGFloat = 800) async -> (png: Data, size: CGSize, duration: Double)?
}
```
- `recordVideo`: dedup by `cipher.dedupHash(reference.path)`; on hit bump createdAt (keep existing blob, caller deletes the new thumbnail like recordImage does); else insert kind "video", body = sealed `reference.encodedJSON()`, blobPath = thumbnailBlobPath, dimensions = "\(width)x\(height)", byteSize = Int(byteSize). `postChange()`, return decrypt(result). NO image-cap enforcement (videos external).
- `softDelete` already nulls blobPath + eagerly deletes the blob if unreferenced; that deletes the THUMBNAIL blob only — the `.mov` is never touched. Verify in test.
- `VideoThumbnail`: `AVURLAsset`; load duration + first video track naturalSize via async `load(...)`; `AVAssetImageGenerator` async `image(at: CMTime(seconds: min(0.1,dur), preferredTimescale: 600))` → CGImage → PNG `Data` → `ImageProcessor.process(data:)` for the ≤maxPixel cap → return thumbnailData + processed.pixelSize + duration. Use modern async AVFoundation (not deprecated `copyCGImage`).

**Steps:**
- [ ] Failing tests: `VideoReferenceTests.test_jsonRoundTrip` (encode→decode equal); `RecordVideoTests.test_recordsVideoRow` (recordImage-style harness: `ClipboardStore(configuration: .testingConfiguration())`, insert a VideoReference + a thumbnail blob path, assert item kind "video", dimensions "1920x1080", recentItems contains it, body decodes back to the reference); `RecordVideoTests.test_softDeleteKeepsExternalMovFile` (create a temp `.mov` file on disk, record a video referencing it, softDelete the item, assert the temp `.mov` STILL exists on disk).
- [ ] `make test` → FAIL.
- [ ] Implement `VideoReference`, `ItemKind.video`, `recordVideo`, `VideoThumbnail`.
- [ ] `make test` → PASS.
- [ ] Commit.

---

### Task 4: Drawer video card + callbacks + paste + Videos tab
**Files:** Modify `ClipboardManager/UI/Drawer/ClipboardCard.swift`, `DrawerView.swift`, `DrawerWindow.swift`, `DrawerWindowController.swift`, `ClipboardManager/Services/PasteInjector.swift`, `ClipboardManager/ClipboardViewModel.swift`. Test: extend `PasteInjectorTests` if present.

**Interfaces (consume Task 3):** `VideoReference`, `ItemKind.video`.
**Produce:** `ClipboardCard.onPlayVideo: ((Item) -> Void)?`; `DrawerTab.videos`.

**Steps (UI mostly build-verified; add a unit test for the paste case):**
- [ ] In `ClipboardCard`: `private var isVideo: Bool { item.kind == "video" }`; `content` routes `isVideo → videoContent`. `videoContent`: if thumbnail (item.blobPath + blobStore + ImageCache) → show it `.aspectRatio(.fill)`; else film-strip gradient. Overlay a centered play badge (`Image(systemName: "play.circle.fill")`) and, if `VideoReference` decodes, a duration capsule (bottom-trailing) using `formattedDuration`. Context menu: add `Button("Play") { onPlayVideo?(item) }` and reuse `Button("Reveal in Finder") { onRevealInFinder?(item) }` for video (extend the `item.kind == "file"` condition to also show for video, or add a video branch). Keep Copy/Pin/Delete.
- [ ] Add `onPlayVideo` through `DrawerView` (property + pass into `ClipboardCard`), `DrawerWindow` (init param + store), `DrawerWindowController` (init param + `handlePlayVideo`). `handlePlayVideo`: decode `VideoReference`, `NSWorkspace.shared.open(URL(fileURLWithPath: ref.path))`, `hide()`. Extend `handleReveal` to also handle `kind == "video"` (decode VideoReference for the path).
- [ ] `PasteInjector.writeToPasteboard`: add `case "video":` decode `VideoReference`, `pasteboard.writeObjects([URL(fileURLWithPath: ref.path) as NSURL])`. Add test `test_videoWritesFileURL` if `PasteInjectorTests` exists.
- [ ] `ClipboardViewModel`: `DrawerTab` add `.videos` ("Videos"); `refilter` add `case .videos: list = list.filter { $0.kind == "video" }`.
- [ ] `make test` → PASS; `make build` → SUCCEEDED.
- [ ] Commit.

---

### Task 5: `RecordingChooserPanel` + `CountdownOverlay`
**Files:** Create `ClipboardManager/UI/Recording/RecordingChooserPanel.swift`, `ClipboardManager/UI/Recording/CountdownOverlay.swift`.

**Produce:**
```swift
// A small borderless nonactivating panel (like AnnotationPanel) centered on the
// target screen with three buttons.
enum RecordingChoice { case region, fullScreen, cancel }
final class RecordingChooserPanel { /* show(onChoice: @escaping (RecordingChoice) -> Void) */ }
// Full-screen borderless nonactivating panel showing a 3→2→1 countdown then calls onDone.
final class CountdownOverlay { /* show(on screen: NSScreen, from seconds: Int = 3, onDone: @escaping () -> Void, onCancel: @escaping () -> Void) */ }
```
- Build these as `NSPanel` subclasses or controllers hosting SwiftUI, mirroring `ScreenFreezeWindow` (borderless, `.nonactivatingPanel`, `isFloatingPanel`, `level = CGShieldingWindowLevel()`, clear background) so they behave in the menu-bar-only app. CountdownOverlay uses a Timer (1s tick) to count 3→2→1 and a big centered number over a dim backdrop; Esc cancels.
- These are exercised by Task 6; here just build them and confirm they compile.
- [ ] Implement both. `make build` → SUCCEEDED. Commit.

---

### Task 6: Orchestration — hotkey, chooser→selection→countdown→record→stop→finalize, menu-bar Stop
**Files:** Modify `ClipboardManager/App/AppCoordinator.swift`, `ClipboardManager/Services/HotkeyService.swift`, `ClipboardManager/UI/MenuBar/MenuBarController.swift`, `ClipboardManager/UI/Preferences/ShortcutsPane.swift`.

**Consume:** Tasks 1–5.

**Steps:**
- [ ] `HotkeyService`: add `KeyboardShortcuts.Name.startRecording = Self("startRecording")` (no default); add `var onStartRecording: @MainActor () -> Void = {}`; register in `start()`.
- [ ] `ShortcutsPane`: add a "Screen Recording" section with `KeyboardShortcuts.Recorder("Start / Stop Recording", name: .startRecording)`.
- [ ] `MenuBarController`: add a `onToggleRecording: @MainActor () -> Void` and `isRecording: @MainActor () -> Bool` (default `{ false }`); add a menu item whose title is "Record Screen" or "Stop Recording" based on `isRecording()` (update in `menuWillOpen`/`refreshStatus`). Keep existing API back-compatible (new params have defaults).
- [ ] `AppCoordinator`: hold `ScreenRecorder` + recording state. Wire `hotkey.onStartRecording = { [weak self] in self?.toggleRecording() }` and the menu-bar `onToggleRecording`. Implement:
  - `toggleRecording()`: if recording → `stopRecording()`; else `beginRecordingFlow()`.
  - `beginRecordingFlow()`: show `RecordingChooserPanel`. On `.region` → present `SelectionOverlayNSView` (reuse), on selection compute global rect via `ScreenCaptureGeometry.screencaptureRect`/the selection→global mapping used in `captureAndAnnotate`; on `.fullScreen` → whole screen-under-mouse global rect; `.cancel` → abort.
  - After a rect is chosen → `CountdownOverlay.show(on: screen)` → onDone → start `ScreenRecorder.start(globalRect:audio: Settings().recordAudio, outputURL: <temp .mov>, onFinish:)`. Set recording state; refresh menu bar.
  - `stopRecording()`: `recorder.stop()`. In `onFinish(url)`: if url valid → move into `RecordingFolder.resolve(bookmark: Settings().recordingSaveBookmark)` via `RecordingFolder.moveIntoFolder` (timestamp `Int64(Date().timeIntervalSince1970)`); `await VideoThumbnail.firstFrame(url:)`; if thumb → `blobStore.write` the PNG; build `VideoReference` (name, byteSize/mtime from FileManager attrs, duration/size from thumbnail result) → `store.recordVideo(reference:thumbnailBlobPath:sourceApp:"Screen Recording")` (delete the new thumbnail blob if recordVideo deduped/dropped, like recordImage). Clear recording state; refresh menu bar.
  - Use the **screen under the mouse** (mirror `presentScreenFreeze`) and pause/skip nothing on the monitor (recording doesn't touch the pasteboard).
  - Add a global Esc key monitor during chooser/countdown/selection to cancel cleanly.
- [ ] `make test` → PASS; `make build` → SUCCEEDED.
- [ ] Commit.

---

### Task 7: Final verification
- [ ] `make test` 2>&1 | tail — full suite green, report count.
- [ ] `make build` — BUILD SUCCEEDED.
- [ ] Completeness check vs the spec: every spec section has corresponding code (record flow, region+full, audio setting, folder, drawer video card + tab + play/reveal/copy, soft-delete keeps mov, menu-bar Stop, hotkey).
- [ ] Report any gaps. (Manual run + install handled by the orchestrator after the workflow.)
