# Movable & Editable Text Annotations — Implementation Plan

> Sequential, TDD where feasible. Each task ends with `make test` green (or `make build` for UI-only) and a commit. Spec: `docs/superpowers/specs/2026-06-21-movable-editable-text-annotations-design.md`.

**Goal:** Move and re-edit text labels in both annotation editors (Text tool only).

**Constraints:** `make test` runs the whole suite (xcodebuild). Swift 6 (pure helpers `nonisolated`). Follow existing patterns. Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Read the analogue code before editing: `ClipboardManager/UI/Annotation/ScreenFreezeOverlay.swift` (ScreenFreezeView: `annotationDrag`, `clamp`, `commitText`, `draw`, coordinate space `"freeze"`, fontSize `max(lineWidth*4,8)`) and `ClipboardManager/UI/Annotation/ImageAnnotationView.swift` (AnnotationCanvas: `handleChanged`/`handleEnded`, `toBaseSpace`/`toViewSpace`/`fittedRect`, `onTextTap`; host `ImageAnnotationView`: `pendingText`/`pendingTextPoint`/`showingTextEntry`/`commitText`).

---

### Task 1: `TextAnnotationHitTest` helper + unit tests
**Files:** Create `ClipboardManager/ActionsKit/TextAnnotationHitTest.swift`; Test `ClipboardManagerTests/TextAnnotationHitTestTests.swift`.

**Produce:**
```swift
import AppKit
enum TextAnnotationHitTest {
    static func topmostIndex(rects: [CGRect], containing point: CGPoint) -> Int?
    static func bounds(text: String, origin: CGPoint, fontSize: CGFloat, padding: CGFloat = 6) -> CGRect
}
```
- `topmostIndex`: `rects.enumerated().filter { $0.element.contains(point) }.map(\.offset).max()`.
- `bounds`: measure `(text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)])`; return `CGRect(origin: origin, size: size).insetBy(dx: -padding, dy: -padding)`. (`nonisolated` so tests can call it.)

**Steps:**
- [ ] Failing tests:
  - `test_topmostIndex_pointInsideSingleRect` → rects `[CGRect(0,0,10,10), CGRect(100,100,10,10)]`, point `(5,5)` → 0.
  - `test_topmostIndex_overlapReturnsTopmost` → rects `[CGRect(0,0,50,50), CGRect(10,10,50,50)]`, point `(20,20)` → 1 (higher index wins).
  - `test_topmostIndex_outsideReturnsNil` → point `(999,999)` → nil.
  - `test_topmostIndex_ignoresNullSlots` → rects `[.null, CGRect(0,0,10,10)]`, point `(5,5)` → 1; point `(5,5)` with `[CGRect(0,0,10,10), .null]` → 0.
  - `test_bounds_nonEmptyAndContainsNearOrigin` → `bounds(text: "Hi", origin: CGPoint(x:20,y:20), fontSize: 16)`: assert width/height > 0 and the rect contains `(22, 24)`.
- [ ] `make test` → FAIL.
- [ ] Implement.
- [ ] `make test` → PASS. Commit.

---

### Task 2: `ScreenFreezeView` — move + edit text labels
**Files:** Modify `ClipboardManager/UI/Annotation/ScreenFreezeOverlay.swift`.

**Consume:** `TextAnnotationHitTest`.

**Add state:** `@State private var movingTextIndex: Int?`, `@State private var dragStartLocation: CGPoint?`, `@State private var didMoveText = false`, `@State private var editingTextIndex: Int?`.

**Steps:**
- [ ] Rewrite the `annotationDrag` text path:
  - `.onChanged { v in`:
    - If `dragStartLocation == nil` (drag begin): set `dragStartLocation = v.location`. If `tool == .text` → compute `rects = annotations.map { $0.tool == .text ? TextAnnotationHitTest.bounds(text: $0.text, origin: $0.points.first ?? .zero, fontSize: max($0.lineWidth*4, 8)) : .null }`; `movingTextIndex = TextAnnotationHitTest.topmostIndex(rects: rects, containing: v.location)`.
    - If `movingTextIndex` set: if `hypot(v.location.x-dragStart.x, v.location.y-dragStart.y) > 4` → `didMoveText = true`; if `didMoveText`, set `annotations[i].points = [clamp(v.location)]`. **Return** (do not fall through to draw).
    - Else (no moving index): existing pen/arrow/rectangle onChanged logic (text does nothing here).
  - `.onEnded { v in`:
    - If `movingTextIndex == i`: if `didMoveText` → just reset. Else (tap on label) → `editingTextIndex = i; pendingText = annotations[i].text; pendingTextPoint = nil; showingText = true`.
    - Else if `tool == .text` → existing add: `pendingTextPoint = clamp(v.location); editingTextIndex = nil; pendingText = ""; showingText = true`.
    - Else → existing draft-commit for pen/arrow/rect.
    - Reset `movingTextIndex = nil; dragStartLocation = nil; didMoveText = false`.
- [ ] Update `commitText()`:
  - If `let i = editingTextIndex` (and `i < annotations.count`): if `pendingText.isEmpty` → `annotations.remove(at: i)` else `annotations[i].text = pendingText`. `editingTextIndex = nil`.
  - Else: existing guard + append.
  - Always reset `pendingText`, `pendingTextPoint` at end. Ensure the alert's Cancel also clears `editingTextIndex`.
- [ ] `make build` → SUCCEEDED. Commit.

---

### Task 3: `AnnotationCanvas` + `ImageAnnotationView` — move + edit text labels
**Files:** Modify `ClipboardManager/UI/Annotation/ImageAnnotationView.swift`.

**Consume:** `TextAnnotationHitTest`.

**AnnotationCanvas:** add `@State private var movingTextIndex: Int?`, `@State private var dragStartLocation: CGPoint?`, `@State private var didMoveText = false`; add `var onEditText: (Int) -> Void`.
- In `handleChanged(value, fitted:)`:
  - On drag-begin (`dragStartLocation == nil`): `dragStartLocation = value.location`. If `tool == .text` → build view-space rects: for each annotation, if text → `TextAnnotationHitTest.bounds(text: a.text, origin: toViewSpace(a.points.first ?? .zero, fitted: fitted), fontSize: max(a.lineWidth*4, 8))` else `.null`; `movingTextIndex = topmostIndex(rects, containing: value.location)`.
  - If `movingTextIndex == i`: if moved past 4 pt → `didMoveText = true`; if `didMoveText` set `annotations[i].points = [toBaseSpace(value.location, fitted: fitted)]`. Return (don't draw).
  - Else: existing pen/arrow/rectangle logic (text does nothing on change).
- In `handleEnded(value, fitted:)`:
  - If `movingTextIndex == i`: if `didMoveText` → reset; else → `onEditText(i)`.
  - Else if `tool == .text` → existing `onTextTap(toBaseSpace(value.location, fitted:))`.
  - Else → existing draft append.
  - Reset move state.

**ImageAnnotationView (host):** add `@State private var editingTextIndex: Int?`. Pass `onEditText: { i in editingTextIndex = i; pendingText = annotations[i].text; pendingTextPoint = nil; showingTextEntry = true }` to `AnnotationCanvas`. Update `commitText()`: if `let i = editingTextIndex, i < annotations.count` → empty deletes (`annotations.remove(at:i)`), else `annotations[i].text = pendingText`; reset `editingTextIndex`. Else existing append. The alert Cancel clears `editingTextIndex` too.

- [ ] `make build` → SUCCEEDED. (Run `make test` to confirm no regressions.) Commit.

---

### Task 4: Final verification
- [ ] `make test` → full suite green (report count).
- [ ] `make build` → BUILD SUCCEEDED.
- [ ] Completeness vs spec: add/move/edit/delete present in BOTH editors; helper unit-tested; only text affected; hit-test view-space in both; Swift 6 clean.
