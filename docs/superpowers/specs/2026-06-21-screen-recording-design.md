# Screen Recording — Design

Date: 2026-06-21
Branch base: `cycle1-stability`

Add screen recording to LimiClip. Recordings save as `.mov` files to a
user-chosen folder; the drawer shows a playable **video** card (thumbnail + play
badge + duration) that points at the file. Only a small first-frame thumbnail is
stored as an (encrypted) blob — never the video itself.

## Decisions (from brainstorming)
- **Storage:** `.mov` saved to a user-picked **Recordings folder**; drawer shows a card referencing it. No large encrypted blobs.
- **Target:** user chooses **Region or Full Screen each time**.
- **Audio:** Settings toggle, **off by default** (mic via `screencapture -g`).
- **Control:** a configurable **Start Recording** hotkey begins the flow; while recording, the menu bar shows **Stop Recording** (and the same hotkey stops).
- **Region picker:** reuse the existing crosshair selection overlay; **3-2-1 countdown** before recording begins.

## Capture flow
1. Start-Recording hotkey → small **chooser** panel (Region / Full Screen / Cancel).
2. Region → reuse `SelectionOverlayNSView` (crosshair) to drag-select; Full → the whole screen under the mouse. Both resolve to a global rect via `ScreenCaptureGeometry.screencaptureRect`.
3. **3-2-1 countdown** overlay on that screen.
4. `ScreenRecorder.start` launches `screencapture -v -R<rect> [-g] <temp.mov>`.
5. Menu bar shows **Stop Recording**; Start hotkey also stops. macOS system recording indicator shows too.
6. Stop → `ScreenRecorder.stop` interrupts the process; it finalizes the `.mov`.
7. Move the finalized file to the Recordings folder as `recording-<timestamp>.mov`.
8. Generate a first-frame thumbnail (`VideoThumbnail` → ≤800px PNG via `ImageProcessor` → `BlobStore`) and call `ClipboardStore.recordVideo`.

> **Empirical-flags requirement:** the exact `screencapture` video flags must be
> verified by actually running the command (e.g. `screencapture -v -V1 -R0,0,200,200 /tmp/t.mov`)
> and confirming a valid, playable `.mov` results, for BOTH region and full-screen
> rects. If `-v` + `-R` does not record a region, fall back to a working
> combination (documented in code). Do not assume.

## Data model
- New `ItemKind.video` (kind column `"video"`).
- New `VideoReference: Codable` (path, name, byteSize, modifiedAt, durationSeconds, width, height) stored as JSON in `Item.body` (sealed), analogous to `FileReference`.
- `ClipboardStore.recordVideo(reference:thumbnailBlobPath:sourceApp:)`: kind `"video"`, body = sealed `VideoReference` JSON, `blobPath` = thumbnail PNG blob (may be nil), `dimensions` = `"WxH"`, dedup by path hash. Subject to normal history limit/retention; **soft-delete must NOT delete the user's `.mov`** (only the thumbnail blob is GC'd, exactly like file references are never deleted from disk).

## Drawer integration
- `ClipboardCard`: `isVideo` branch renders the thumbnail (via `ImageCache`) with a centered **play badge** + a duration capsule; falls back to a film-strip SF Symbol if no thumbnail. New `onPlayVideo` callback (threaded through `DrawerView` → `DrawerWindow` → `DrawerWindowController`, same pattern as `onAnnotate`). Context menu: **Play, Reveal in Finder, Copy, (Pin/Unpin), Delete**.
- `DrawerWindowController`: `handlePlayVideo` opens the `.mov` (`NSWorkspace.shared.open`); `handleReveal` extended to video kind; copy of a video writes the file URL.
- `PasteInjector.writeToPasteboard`: `case "video"` decodes `VideoReference` and writes the file URL (like `file`).
- `DrawerTab`: add `.videos` ("Videos") filtering `kind == "video"`.

## Settings
- `Settings.Key.recordingSaveFolder` (security-scoped bookmark `Data?`) + `recordAudio` (Bool, default false).
- `RecordingFolder` helper (resolve/makeBookmark/move-into-folder), analogous to `AnnotationFolder`; fallback `~/Movies`.
- `GeneralPane`: a "Recording" section — folder picker + "Record microphone audio" toggle.
- `HotkeyService.Name.startRecording` (no default) + `ShortcutsPane` recorder row.

## Components (each small + testable)
- `ScreenRecorder` (Service, @MainActor): process lifecycle; **pure** `arguments(globalRect:audio:outputPath:)` builder (unit-tested). Empirically-verified flags.
- `RecordingFolder` (Service): bookmark resolve/create + move file in; path logic unit-tested.
- `VideoReference` (Store): Codable round-trip unit-tested.
- `ClipboardStore.recordVideo` + `ItemKind.video`: store round-trip + soft-delete-keeps-file unit-tested.
- `VideoThumbnail` (helper): async first-frame PNG + size + duration via AVFoundation (modern async API; `copyCGImage` is deprecated on macOS 26).
- `RecordingChooserPanel` + `CountdownOverlay` (UI, borderless nonactivating panels like `AnnotationPanel`/`ScreenFreezeWindow`).
- `AppCoordinator` orchestration + `MenuBarController` Stop item + `HotkeyService` shortcut.

## Permissions
Screen Recording (already granted). Microphone only when audio is enabled (prompt then). `screencapture -g` attributes the mic prompt to LimiClip.

## Error handling
- No folder set / stale bookmark → fall back to `~/Movies`, log.
- `screencapture` launch failure or non-zero exit / missing output file → log, abort, no drawer item, clear recording state.
- Thumbnail generation failure → still record the video item with `blobPath = nil` (card shows film-strip placeholder).
- Start pressed while already recording → treated as Stop (toggle), never two concurrent recordings.

## Testing
Unit: args builder (region rect, audio on/off), `RecordingFolder` resolve/fallback/move, `VideoReference` JSON round-trip, `recordVideo` store round-trip + dedup + soft-delete-keeps-`.mov`. Integration: `ScreenRecorder` runs `screencapture -v -V1` to a temp file and asserts a valid `.mov` (validates the real flags). UI verified by build + manual run.

## Sequencing
1. `ScreenRecorder` + args (+ empirical flag check)
2. `RecordingFolder` + settings + GeneralPane UI
3. `VideoReference` + `ItemKind.video` + `recordVideo` + `VideoThumbnail`
4. Drawer: `ClipboardCard` video + callbacks + `PasteInjector` + `DrawerTab.videos`
5. `RecordingChooserPanel` + `CountdownOverlay`
6. `AppCoordinator` orchestration + `MenuBarController` Stop + `HotkeyService`/`ShortcutsPane`
7. Final verification: full build+test green, completeness vs this spec, install.
