# Copy/Paste Consistency + Image Annotation — Design

Date: 2026-06-18
Branch base: `cycle1-stability`

Three pieces of work, sequenced: two clipboard-consistency bugs, then a new
image-annotation feature. Each ships with tests.

---

## Part 1 — Bug: first ⌘C is not captured (only the second copy lands)

### Symptom
Sometimes a copy is not saved on the first ⌘C; repeating ⌘C saves it.

### Root cause (to confirm via systematic-debugging)
`PasteboardMonitor.tick()` advances `lastChangeCount` in a `defer` block on
*every* tick where the change count differs — regardless of whether anything
usable was read:

```swift
private func tick() {
    let current = pasteboard.changeCount
    defer { lastChangeCount = current }   // <-- always commits
    guard current != lastChangeCount else { return }
    ...
    route()
}
```

The 250 ms poll can land between an app's `clearContents()` (which already
bumps `changeCount`) and its subsequent data write — or before a lazy
pasteboard provider has supplied data. `route()` then finds an empty
pasteboard, records nothing, but `lastChangeCount` is still advanced, so the
copy is lost until the next ⌘C bumps the count again.

### Fix
`route()` returns a result that distinguishes:

- **handled** — recognized content was recorded, OR a deliberate skip occurred
  (concealed type, excluded bundle, strict-capture unknown-source). These are
  terminal: commit `lastChangeCount`.
- **empty** — no recognized content found yet (transient empty / not-yet-written
  pasteboard). Do NOT commit `lastChangeCount`, so the next poll re-reads.

`tick()` only advances `lastChangeCount` on **handled**. On **empty** it leaves
`lastChangeCount` unchanged, bounded by a per-`changeCount` retry budget
(3 polls ≈ 750 ms) so a genuinely empty pasteboard is not reprocessed forever.
State to track: the pending change count and its attempt counter; reset when a
new change count appears.

### Tests
- A change count that differs but yields no usable content does NOT advance
  `lastChangeCount` (re-routes on the next tick).
- Once content appears on a later tick, it is recorded exactly once.
- After the retry budget is exhausted with no content, the monitor gives up and
  advances (no infinite reprocessing).
- A deliberate skip (concealed / excluded / strict-mode) counts as handled and
  advances immediately — no retry.

---

## Part 2 — Bug: image previews not showing in the panel

### Symptom
Image items don't render a preview in the drawer.

### Approach: debug against the live install BEFORE committing a fix
Follow systematic-debugging. Gather evidence in order:

1. Count `kind='image'` rows in the live SQLite DB
   (`~/Library/Application Support/Clipboard Manager/clipboard.sqlite`). Are
   images being captured at all post-100MB-cap?
2. For an image row, confirm its thumbnail blob file exists on disk under the
   blob store root.
3. Confirm `BlobStore.read(relativePath:)` + decrypt returns bytes for that
   blob (text capture works, so the cipher is healthy — but verify image blobs
   specifically).
4. Confirm `NSImage(data:)` decodes those bytes.
5. Confirm `decrypt()` on a recorded image `Item` preserves `blobPath` (the
   card renders from `item.blobPath`, the plaintext column).

Write a failing test reproducing whatever the evidence identifies, then fix.
Candidate causes (do not pre-commit): blob decrypt path for images,
`decrypt()` dropping `blobPath`, or `NSImage` decode of the thumbnail PNG.

### Tests
A regression test at the layer the root cause lives in (e.g. round-trip
record→decrypt→read→decode for an image item).

---

## Part 3 — Feature: annotate images before copy/save

### Key constraint
Drawer images are stored as **downsampled thumbnails (≤800px PNG)**, not the
original bytes. The original is never persisted. Annotation therefore operates
on the thumbnail. Acceptable for v1; documented limitation.

### Entry point
An **"Annotate"** action added to every image card's context menu in
`ClipboardCard`. Capture flows (⌘⇧A, ⌘⇧4 watcher) are unchanged.

### Components
- **`ImageAnnotator` (ActionsKit, no UI deps):** the annotation model
  (an ordered array of typed annotations: pen stroke, arrow, rectangle, text)
  plus `flatten(base:annotations:) -> Data` that composites annotations over the
  base image and returns PNG bytes. Unit-testable in isolation.
- **`AnnotationCanvas` (SwiftUI):** renders the base image + overlay of the
  current annotation array; handles drag/tap gestures to append/edit
  annotations for the active tool.
- **`ImageAnnotationView` (SwiftUI window/sheet):** thin shell — toolbar
  (tool picker, color, thickness), the canvas, and the three output actions.
- **Folder bookmark helper:** resolves the security-scoped bookmark for the
  chosen save folder; unit-testable path logic.

### Tools (v1)
Freehand pen, arrow, rectangle, text label. Each carries a color and line
thickness. Annotations are vector and editable until flatten (supports undo of
the last annotation).

### Output destinations (flatten → PNG)
1. **Copy to clipboard** — write flattened PNG to `NSPasteboard`.
2. **Save to chosen folder** — write `annotated-<timestamp>.png` to the
   folder from the new `annotationSaveFolder` setting.
3. **Save into history** — feed flattened PNG through
   `ImageProcessor → BlobStore → ClipboardStore.recordImage` as a new item.

(The user may choose any subset; the editor offers all three as actions.)

### New settings
- `annotationSaveFolder` — security-scoped bookmark (`Data`) in `Settings`,
  with a default of `~/Pictures` (or unset → prompt on first save-to-folder).
- A Settings row (in `GeneralPane` or a small new section) with an
  `NSOpenPanel` folder picker showing the current path.

### Tests
- `ImageAnnotator.flatten` produces non-empty PNG bytes larger than / different
  from the base for each tool; decodes back to an image of the expected size.
- Undo removes the last annotation.
- Folder-bookmark helper resolves/falls back correctly.
- Save-into-history path records a new image row (round-trip).

---

## Sequencing
1. Part 1 (monitor retry) — isolated, well-covered by unit tests.
2. Part 2 (image preview) — debug-driven; fix follows evidence.
3. Part 3 (annotation) — feature, built on a testable `ImageAnnotator` core.

Each part is committed separately with its tests green.
