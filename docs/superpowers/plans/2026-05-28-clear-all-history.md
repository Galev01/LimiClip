# Clear All History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Clear" button to the drawer's bottom-right that hard-deletes all non-pinned clipboard history after a native confirmation dialog.

**Architecture:** `ClipboardStore.clearAll()` does the delete and posts `clipboardStoreDidChange`; `DrawerWindowController` owns the `NSAlert` confirmation; `DrawerView` renders the button. The closure is threaded `DrawerWindowController → DrawerWindow.init() → DrawerView`.

**Tech Stack:** Swift 6, SwiftUI + AppKit, GRDB SQLite, XCTest.

---

## File Map

| File | Change |
|------|--------|
| `ClipboardManager/Store/ClipboardStore.swift` | Add `clearAll()` method |
| `ClipboardManagerTests/ClipboardStoreTests.swift` | Add two tests for `clearAll()` |
| `ClipboardManager/UI/Drawer/DrawerView.swift` | Add `onClearAll` optional closure property + Clear button in `bottomBar` |
| `ClipboardManager/UI/Drawer/DrawerWindow.swift` | Add `onClearAll` required parameter, pass to `DrawerView` |
| `ClipboardManager/UI/Drawer/DrawerWindowController.swift` | Add `handleClearAll()` with `NSAlert`; pass closure to `DrawerWindow` |

---

## Task 1: ClipboardStore.clearAll()

**Files:**
- Modify: `ClipboardManager/Store/ClipboardStore.swift`
- Test: `ClipboardManagerTests/ClipboardStoreTests.swift`

- [ ] **Step 1: Write two failing tests** in `ClipboardStoreTests.swift`, after the existing `testPinnedItemSurvivesPurge` test:

```swift
func testClearAllDeletesNonPinnedItems() throws {
    let store = try makeStore()
    let a = try store.recordText("item-a", sourceApp: nil, sourceBundleId: nil)
    let b = try store.recordText("item-b", sourceApp: nil, sourceBundleId: nil)
    let c = try store.recordText("pinned-item", sourceApp: nil, sourceBundleId: nil)
    try store.setPinned(itemId: c!.id!, pinned: true)

    try store.clearAll()

    let remaining = try store.recentItems(limit: 10)
    XCTAssertEqual(remaining.count, 1, "only the pinned item should remain")
    XCTAssertEqual(remaining.first?.body, "pinned-item")
    XCTAssertNil(remaining.first { $0.id == a?.id })
    XCTAssertNil(remaining.first { $0.id == b?.id })
}

func testClearAllOnEmptyStoreSucceeds() throws {
    let store = try makeStore()
    XCTAssertNoThrow(try store.clearAll())
    XCTAssertEqual(try store.countItems(), 0)
}
```

- [ ] **Step 2: Run the tests — verify they fail**

```bash
xcodebuild -scheme ClipboardManager -destination 'platform=macOS' test \
  -only-testing ClipboardManagerTests/ClipboardStoreTests/testClearAllDeletesNonPinnedItems \
  -only-testing ClipboardManagerTests/ClipboardStoreTests/testClearAllOnEmptyStoreSucceeds \
  2>&1 | grep -E "(PASS|FAIL|error:)"
```

Expected: both FAIL with `has no member 'clearAll'`.

- [ ] **Step 3: Implement `clearAll()` in `ClipboardStore.swift`**

Add after `func softDelete(itemId:)` (around line 263), inside `// MARK: - Soft delete`:

```swift
/// Hard-deletes all non-pinned, non-soft-deleted items. Pinned items are preserved.
func clearAll() throws {
    _ = try queue.write { db in
        try Item.filter(Item.Columns.pinned == false && Item.Columns.deletedAt == nil)
            .deleteAll(db)
    }
    postChange()
}
```

- [ ] **Step 4: Run the tests — verify they pass**

```bash
xcodebuild -scheme ClipboardManager -destination 'platform=macOS' test \
  -only-testing ClipboardManagerTests/ClipboardStoreTests/testClearAllDeletesNonPinnedItems \
  -only-testing ClipboardManagerTests/ClipboardStoreTests/testClearAllOnEmptyStoreSucceeds \
  2>&1 | grep -E "(PASS|FAIL|error:)"
```

Expected: both PASS.

- [ ] **Step 5: Run the full test suite — verify nothing is broken**

```bash
xcodebuild -scheme ClipboardManager -destination 'platform=macOS' test \
  2>&1 | grep -E "(PASS|FAIL|All tests)" | tail -5
```

Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/gal.lev/Clipboard add \
  ClipboardManager/Store/ClipboardStore.swift \
  ClipboardManagerTests/ClipboardStoreTests.swift
git -C /Users/gal.lev/Clipboard commit -m "feat: add ClipboardStore.clearAll() — hard-delete non-pinned items"
```

---

## Task 2: DrawerView — onClearAll closure + Clear button

**Files:**
- Modify: `ClipboardManager/UI/Drawer/DrawerView.swift`

`DrawerView` already has optional closure properties for each action (`onPaste`, `onDelete`, `onPin`, etc.), all defaulting to `nil`. Add `onClearAll` the same way, then add the Clear button to `bottomBar`.

- [ ] **Step 1: Add the `onClearAll` closure property**

In `DrawerView.swift`, add after `var onPin: ((Item, Bool) -> Void)? = nil` (around line 13):

```swift
var onClearAll: (() -> Void)? = nil
```

- [ ] **Step 2: Update `bottomBar` to include the Clear button**

Replace the existing `bottomBar` computed property:

```swift
private var bottomBar: some View {
    HStack {
        let count = viewModel.filteredItems.count
        let total = viewModel.items.count
        Text(viewModel.searchQuery.isEmpty
             ? "\(count) item\(count == 1 ? "" : "s")"
             : "\(count) of \(total) matched")
        Spacer()
        Text("⏎ paste · ⌫ delete · / search")
        if viewModel.items.contains(where: { !$0.pinned }) {
            Button("Clear") { onClearAll?() }
                .foregroundStyle(Color.red.opacity(0.8))
                .buttonStyle(.plain)
        }
    }
    .font(.system(size: 11))
    .foregroundStyle(.primary.opacity(dark ? 0.2 : 0.18))
    .padding(.horizontal, 20)
    .padding(.bottom, 10)
}
```

The button is hidden automatically when every item is pinned (or history is empty), because `contains(where: { !$0.pinned })` returns `false` in that case.

- [ ] **Step 3: Build — verify it compiles**

```bash
xcodebuild -scheme ClipboardManager -destination 'platform=macOS' build \
  2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`. (`DrawerWindow` still calls `DrawerView` without `onClearAll`, which is fine — the parameter defaults to `nil` so no call-site breakage.)

- [ ] **Step 4: Commit**

```bash
git -C /Users/gal.lev/Clipboard add ClipboardManager/UI/Drawer/DrawerView.swift
git -C /Users/gal.lev/Clipboard commit -m "feat: add Clear button to DrawerView bottom bar"
```

---

## Task 3: Wire DrawerWindow + DrawerWindowController

**Files:**
- Modify: `ClipboardManager/UI/Drawer/DrawerWindow.swift`
- Modify: `ClipboardManager/UI/Drawer/DrawerWindowController.swift`

These two files must be updated together: adding `onClearAll` as a **required** parameter to `DrawerWindow.init()` immediately breaks the call site in `DrawerWindowController`, so both edits happen in the same task.

- [ ] **Step 1: Add `onClearAll` to `DrawerWindow.init()`**

In `DrawerWindow.swift`, update `init` to accept the new closure and pass it to `DrawerView`.

Replace the `init` signature and `NSHostingView` construction:

```swift
init(
    viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore,
    onPaste: @escaping (Item, Bool) -> Void,
    onCopy: @escaping (Item) -> Void,
    onDelete: @escaping (Item) -> Void,
    onOpenURL: @escaping (Item) -> Void,
    onRevealInFinder: @escaping (Item) -> Void,
    onPin: @escaping (Item, Bool) -> Void,
    onClearAll: @escaping () -> Void,
    accessibilityCheck: @escaping () -> Bool = { true }
) {
    self.viewModel = viewModel
    self.store = store
    self.onPasteCallback = onPaste
    super.init(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    isMovable = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    hidesOnDeactivate = false
    animationBehavior = .none
    isReleasedWhenClosed = false
    titleVisibility = .hidden
    titlebarAppearsTransparent = true

    let host = NSHostingView(rootView: DrawerView(
        viewModel: viewModel, blobStore: blobStore,
        onPaste: onPaste, onCopy: onCopy, onDelete: onDelete,
        onOpenURL: onOpenURL, onRevealInFinder: onRevealInFinder,
        onPin: onPin,
        onClearAll: onClearAll,
        accessibilityCheck: accessibilityCheck
    ))
    host.translatesAutoresizingMaskIntoConstraints = false
    let container = NSView()
    container.addSubview(host)
    NSLayoutConstraint.activate([
        host.topAnchor.constraint(equalTo: container.topAnchor),
        host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    contentView = container
}
```

- [ ] **Step 2: Add `handleClearAll()` to `DrawerWindowController`**

In `DrawerWindowController.swift`, add this method after `handlePin(item:pinned:)`:

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

- [ ] **Step 3: Pass `onClearAll` when constructing `DrawerWindow`**

In `DrawerWindowController.init()`, add a `clearAllHandler` variable alongside the other handler variables, then pass it to `DrawerWindow`:

After the existing handler variable declarations (around line 16), add:

```swift
var clearAllHandler: (() -> Void)!
```

In the `DrawerWindow(...)` call, add after `onPin`:

```swift
onClearAll: { clearAllHandler() },
```

After the `DrawerWindow` init call (around line 44), assign the handler:

```swift
clearAllHandler = { [weak self] in self?.handleClearAll() }
```

- [ ] **Step 4: Build — verify it compiles**

```bash
xcodebuild -scheme ClipboardManager -destination 'platform=macOS' build \
  2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Run full test suite**

```bash
xcodebuild -scheme ClipboardManager -destination 'platform=macOS' test \
  2>&1 | grep -E "(PASS|FAIL|All tests)" | tail -5
```

Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/gal.lev/Clipboard add \
  ClipboardManager/UI/Drawer/DrawerWindow.swift \
  ClipboardManager/UI/Drawer/DrawerWindowController.swift
git -C /Users/gal.lev/Clipboard commit -m "feat: wire Clear All through DrawerWindow and DrawerWindowController"
```
