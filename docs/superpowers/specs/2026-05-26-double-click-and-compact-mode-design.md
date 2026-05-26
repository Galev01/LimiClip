# Design: Double-click to Paste + Compact Popup Mode
Date: 2026-05-26

## Overview

Two independent features:
1. **Double-click to paste** — double-clicking a drawer card pastes the item immediately (same as pressing Enter).
2. **Compact popup mode** — a small cursor-adjacent popup showing the 10 most recent clipboard items; single-click pastes immediately and dismisses.

---

## Feature 1: Double-click to Paste

### Scope
Single change in `DrawerView.swift`. No new files, no new settings.

### Behaviour
- Double-clicking a `ClipboardCard` in the drawer is equivalent to pressing Enter: it writes the item to the pasteboard and synthesizes ⌘V (if Accessibility permission is granted).
- Single-click continues to select (focus) the card without pasting.
- SwiftUI's tap-gesture disambiguation handles the two gestures without requiring a delay timer.

### Implementation
Add `.onTapGesture(count: 2) { onPaste?(item, false) }` immediately before the existing `.onTapGesture { viewModel.jumpTo(index: idx) }` on each `ClipboardCard` inside `cardStrip`. SwiftUI evaluates higher-count gestures first.

---

## Feature 2: Compact Popup Mode

### Overview
An opt-in mode where the global hotkey (or a separate configurable shortcut) opens a small vertical panel near the mouse cursor instead of the full bottom drawer. Designed for speed: one click = paste + dismiss.

### Data
- Source: `viewModel.items[0..<min(10, viewModel.items.count)]` — the 10 most recent items across all types, unfiltered, unsearched.
- The compact popup has no tab bar and no search field.

### Window
**`CompactPopupWindow: NSPanel`**
- Style mask: `.borderless` + `.nonactivatingPanel`
- Window level: `.popUpMenu` (appears above all normal windows)
- Background: `NSColor.clear` (SwiftUI view provides the visual surface)
- Size: 300pt wide, auto-height up to 420pt (scrollable if 10 items exceed)
- Not resizable, not moveable by user

**`CompactPopupWindowController`** (`@MainActor final class`)
- `show(near point: NSPoint)` — positions window above cursor, clamped to screen bounds, then makes it key and orders front
- `hide()` — orders out with a brief fade
- Global event monitor (`.leftMouseDown`, `.rightMouseDown`) dismisses on click-outside
- ESC key handler via `NSEvent.addLocalMonitorForEvents` dismisses on Escape
- Owns the `CompactPopupView` via `NSHostingView`

**Positioning logic:**
```
x = clamp(cursor.x - windowWidth/2, screen.minX + 8, screen.maxX - windowWidth - 8)
y = clamp(cursor.y + 8, screen.minY + 8, screen.maxY - windowHeight - 8)
```

### Views

**`CompactPopupView`**
- Root: `VStack(spacing: 0)` inside a `ScrollView(.vertical)` capped at 420pt
- Visual surface: `VisualEffectBackground` (same `DesignMaterials.drawer` as the main drawer) + matching linear gradient + rounded corners (12pt) + hairline border
- Renders `CompactClipboardCard` for each item
- Dividers between items (`.primary.opacity(0.06)`)
- No header, no footer

**`CompactClipboardCard`**
- Height: ~52pt fixed
- Layout: `HStack(spacing: 10)` — leading icon zone (28pt), text zone (flexible), trailing timestamp (40pt)
- **Icon zone:** for images: 24×24pt `AsyncImage`/`BlobImageView` thumbnail; for text: SF Symbol (`doc.text`, `link`, `doc.plaintext`) in a 24×24 rounded rect with kind-colored tint; for files: SF Symbol (`doc.fill`) in same treatment
- **Text zone:** primary label (truncated, 1 line, 13pt medium) + optional secondary (kind hint or file extension, 11pt secondary)
- **Timestamp:** relative (e.g. "2m", "1h") in 11pt secondary style
- Tap action: calls `onPaste?(item, false)` (paste plain=false for all types)
- Visual hover state: background highlight (`.primary.opacity(0.08)`)

### Settings

**`Settings.swift`**
- Add `Key.compactMode = "compactMode"`
- Add computed property `var compactMode: Bool` (default `false`)

**`HotkeyService.swift`**
- Add `KeyboardShortcuts.Name.toggleCompactPopup` — no default shortcut (user assigns in Preferences)
- Add `onCompactToggle: @MainActor () -> Void` callback
- Register handler in `start()`

**`GeneralPane.swift`**
- Add `@AppStorage(Settings.Key.compactMode) private var compactMode: Bool = false`
- Add `Toggle("Compact Mode", isOn: $compactMode)` inside the existing "Drawer" section, below the hover preview toggle

**`ShortcutsPane.swift`**
- Add `KeyboardShortcuts.Recorder("Compact popup", name: .toggleCompactPopup)` row

**`AppCoordinator.swift`**
- Instantiate `CompactPopupWindowController(viewModel:, blobStore:, store:, injector:)`
- Pass `onCompactToggle` closure to `HotkeyService` that calls `compactPopup.toggle(near: NSEvent.mouseLocation)`

### Dismissal
The compact popup dismisses on:
1. Item tap (paste + dismiss)
2. Click outside the window (global monitor)
3. ESC key (local monitor)

### Error handling
- If `viewModel.items` is empty, show a single "No items yet" placeholder row (same style as `EmptyStateView` but compact, no illustration).

---

## Files Changed

| File | Change |
|---|---|
| `ClipboardManager/UI/Drawer/DrawerView.swift` | Add double-tap gesture to cardStrip |
| `ClipboardManager/Settings.swift` | Add `compactMode` key + property |
| `ClipboardManager/Services/HotkeyService.swift` | Add `toggleCompactPopup` name + callback |
| `ClipboardManager/App/AppCoordinator.swift` | Wire compact popup controller + hotkey |
| `ClipboardManager/UI/Preferences/GeneralPane.swift` | Add compact mode toggle |
| `ClipboardManager/UI/Preferences/ShortcutsPane.swift` | Add compact popup shortcut recorder |
| `ClipboardManager/UI/Compact/CompactPopupWindow.swift` | New — NSPanel subclass |
| `ClipboardManager/UI/Compact/CompactPopupWindowController.swift` | New — controller |
| `ClipboardManager/UI/Compact/CompactPopupView.swift` | New — root SwiftUI view |
| `ClipboardManager/UI/Compact/CompactClipboardCard.swift` | New — row item view |

---

## Testing

- `DrawerView` double-tap: unit-test via `onPaste` callback spy (if testable via `XCTest`); smoke test manually in running app.
- `CompactPopupWindowController` positioning: unit-test the `x/y` clamping logic with known screen/cursor values (pure function extractable to `CompactPopupGeometry`).
- `CompactClipboardCard` rendering: SwiftUI preview with text, image, and file item fixtures.
- Manual smoke: toggle compact mode on, press shortcut, click an item, verify paste.

---

## Out of Scope

- Search / filtering within the compact popup
- Keyboard navigation within the compact popup (arrow keys, ⌫)
- Compact popup animation (beyond system fade)
- Per-item context menu in compact popup
