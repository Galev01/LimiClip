# Movable & Editable Text Annotations — Design

Date: 2026-06-21
Branch: `cycle1-stability`

Let users reposition and re-edit text labels they've added with the annotation
**Text** tool, in both editors: the ⌘⇧A in-place screenshot editor
(`ScreenFreezeView`) and the drawer-image editor (`ImageAnnotationView` /
`AnnotationCanvas`). Scope: **text labels only** (pen/arrow/rectangle unchanged).

## Behavior (Text tool active)
- **Tap empty space** → add a new label (unchanged).
- **Press-and-drag an existing label** → move it; release commits.
- **Tap an existing label** (press + release without moving) → re-open the text
  prompt **pre-filled**; confirming updates the label, **clearing it deletes** the label.

Distinguish the three by: on drag-begin, hit-test existing text labels at the
press point. If one is hit, track it; if the pointer moves past a small
threshold (~4 pt) it's a **move**, otherwise on release it's an **edit**. No hit
→ the press is an **add** (existing flow).

## Shared helper (pure, unit-tested)
`ClipboardManager/ActionsKit/TextAnnotationHitTest.swift`:
```swift
enum TextAnnotationHitTest {
    /// Index of the TOPMOST (last-drawn) rect containing `point`, or nil.
    /// Indices map 1:1 to the input array; use `.null` for non-text slots.
    static func topmostIndex(rects: [CGRect], containing point: CGPoint) -> Int?
    /// Bounds of a label drawn from top-left `origin` at `fontSize`, padded.
    /// Measures the string via NSAttributedString(systemFont).
    static func bounds(text: String, origin: CGPoint, fontSize: CGFloat, padding: CGFloat = 6) -> CGRect
}
```
- `topmostIndex`: among rects containing `point`, return the largest index (drawn last = on top). `CGRect.null.contains(_)` is false, so non-text slots never match.
- `bounds`: `NSAttributedString(string:attributes:[.font: NSFont.systemFont(ofSize: fontSize)]).size()` → `CGRect(origin, size).insetBy(dx:-padding, dy:-padding)`. Text is drawn with `.topLeading` anchor, so bounds extend down/right from `origin`.

## Coordinate handling
Hit-test in **view space** in both editors (matches the gesture location and the
on-screen font size `lineWidth × 4`):
- `ScreenFreezeView` — annotation points are already view-space; build a rect per
  annotation (text → `bounds(text, origin, fontSize: max(lineWidth*4, 8))`, else
  `.null`), aligned to the `annotations` index; test against the gesture location
  (coordinate space `"freeze"`). Moving sets `annotations[i].points = [clamp(loc)]`.
- `AnnotationCanvas` — points are base-image space; convert each text origin
  base→view via `toViewSpace`, build view-space rects, test against the gesture's
  view location. Moving sets `annotations[i].points = [toBaseSpace(loc)]`.

## State & wiring
- **ScreenFreezeView** (single view owns `annotations` @State): add
  `movingTextIndex: Int?`, `dragStart: CGPoint?`, `didMoveText: Bool`,
  `editingTextIndex: Int?`. Text-tool branch of `annotationDrag` implements
  hit→move/edit; empty→add. `commitText()` branches on `editingTextIndex`
  (update or delete-if-empty) vs append.
- **AnnotationCanvas** (mutates `@Binding annotations`): add the same move state;
  moving mutates the binding directly. Add `var onEditText: (Int) -> Void`
  callback for the tap-to-edit case. Keep `onTextTap` for add.
- **ImageAnnotationView** (host): add `editingTextIndex: Int?`; set it from
  `onEditText` and pre-fill `pendingText`; `commitText()` branches update/delete
  vs append. The text-entry alert title stays "Add Text" for add and becomes
  "Edit Text" for edit (or keep one title; cosmetic).

`Annotation` model is unchanged.

## Error handling / edge cases
- Move is clamped to the selection (ScreenFreezeView) / stays in base space (canvas).
- Editing to empty string removes the label.
- Hit-testing only engages when the **Text** tool is active.
- Deleting via empty edit must use the SAME index captured at edit time (guard against array bounds).

## Testing
Unit: `TextAnnotationHitTest.topmostIndex` (point inside one rect; point in
overlap returns the higher/topmost index; point outside → nil; `.null` slots
ignored) and `bounds` (non-empty size, contains a point just inside the origin).
UI: build + manual (add, move, edit, delete a label in both editors).

## Sequencing
1. `TextAnnotationHitTest` + unit tests.
2. `ScreenFreezeView` move + edit.
3. `AnnotationCanvas` + `ImageAnnotationView` move + edit.
4. Final verify: full build + test green; manual checklist.
