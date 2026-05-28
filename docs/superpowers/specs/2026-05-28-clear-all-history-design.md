# Clear All History — Design Spec

**Date:** 2026-05-28
**Status:** Approved

## Summary

Add a "Clear" button to the right end of the drawer's bottom bar. Tapping it shows a native confirmation dialog, then hard-deletes all non-pinned clipboard history. Pinned items are preserved.

---

## Feature Behaviour

- **Trigger:** "Clear" text button, far right of the bottom bar in `DrawerView`
- **Confirmation:** Native `NSAlert` with:
  - Title: `"Clear clipboard history?"`
  - Informative text: `"All items will be removed. Pinned items will be kept."`
  - Buttons: **Clear** (destructive style) and **Cancel**
- **Effect:** Hard-deletes all rows where `pinned = 0 AND deletedAt IS NULL`
- **Scope:** Clears all non-pinned items regardless of active tab or search query
- **Pinned items:** Always preserved
- **Post-clear:** `clipboardStoreDidChange` notification fires; `ClipboardViewModel` reloads automatically — drawer empties instantly

---

## Components

### 1. `ClipboardStore.clearAll()`

New method in `ClipboardManager/Store/ClipboardStore.swift`.

```swift
func clearAll() throws {
    _ = try queue.write { db in
        try Item.filter(Item.Columns.pinned == false && Item.Columns.deletedAt == nil)
            .deleteAll(db)
    }
    postChange()
}
```

- Hard-delete (not soft-delete) — user explicitly chose to wipe history
- Pinned rows (`pinned = 1`) and already-soft-deleted rows are untouched
- Calls `postChange()` so `ClipboardViewModel` reloads via existing notification path

### 2. `DrawerView` — Clear button

Added to the `bottomBar` computed property in `ClipboardManager/UI/Drawer/DrawerView.swift`.

- New closure property: `var onClearAll: (() -> Void)? = nil`
- Button: `"Clear"` label, `font-size: 11`, red foreground (`Color.red.opacity(0.8)`), placed after the keyboard hint on the far right
- Hidden when there are no non-pinned items (nothing to clear): `if viewModel.items.contains(where: { !$0.pinned })`
- Tap calls `onClearAll?()`

### 3. `DrawerWindowController` — wiring and confirmation

In `ClipboardManager/UI/Drawer/DrawerWindowController.swift`:

- Passes `onClearAll: { [weak self] in self?.handleClearAll() }` when constructing `DrawerWindow`
- `handleClearAll()` shows the `NSAlert` on the main thread; on **Clear** confirmation calls `store.clearAll()`

```swift
private func handleClearAll() {
    let alert = NSAlert()
    alert.messageText = "Clear clipboard history?"
    alert.informativeText = "All items will be removed. Pinned items will be kept."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Clear")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    do {
        try store.clearAll()
    } catch {
        Log.drawer.error("clearAll failed: \(error.localizedDescription, privacy: .public)")
    }
}
```

### 4. `DrawerWindow` — closure threading

`DrawerWindow.init()` needs one new parameter `onClearAll: @escaping () -> Void`, passed straight through to `DrawerView`. This is a thin, mechanical change — same pattern as `onDelete` and `onPin` in the existing init signature. Closures flow: `DrawerWindowController` → `DrawerWindow.init(onClearAll:)` → `DrawerView(onClearAll:)`.

---

## Data Flow

```
User taps "Clear"
  → onClearAll() closure
  → DrawerWindowController.handleClearAll()
  → NSAlert.runModal() → user confirms
  → ClipboardStore.clearAll()
  → DELETE FROM items WHERE pinned=0 AND deletedAt IS NULL
  → postChange() → clipboardStoreDidChange notification
  → ClipboardViewModel.reload()
  → DrawerView re-renders (empty state if no pinned items)
```

---

## Acceptance Criteria

- [ ] "Clear" button appears in the bottom-right of the drawer
- [ ] Button is hidden when all items are pinned (or history is already empty)
- [ ] Confirmation dialog appears with correct title, message, and button labels
- [ ] Cancelling the dialog leaves history unchanged
- [ ] Confirming deletes all non-pinned, non-soft-deleted items
- [ ] Pinned items remain after clearing
- [ ] Drawer updates immediately after clearing (empty state or pinned-only view)
- [ ] No crash or error when history is already empty

---

## Out of Scope

- Clearing only the currently visible (filtered) tab — this clears all history
- Undo / soft-delete for the clear action
- Keyboard shortcut for Clear All
