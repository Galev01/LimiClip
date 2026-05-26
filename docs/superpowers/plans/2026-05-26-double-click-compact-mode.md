# Double-click to Paste + Compact Popup Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add double-click-to-paste on drawer cards and a cursor-adjacent compact popup mode showing the 10 most recent clipboard items.

**Architecture:** Feature 1 is a one-line gesture addition in `DrawerView`. Feature 2 follows the exact same NSPanel + controller + SwiftUI pattern as the existing drawer: `CompactPopupWindow` (NSPanel subclass), `CompactPopupWindowController` (@MainActor manager), and `CompactPopupView` + `CompactClipboardCard` (SwiftUI). A pure `CompactPopupGeometry` helper handles cursor-relative positioning with screen-edge clamping (unit-tested). Settings, hotkey name, and AppCoordinator are updated to wire it all up.

**Tech Stack:** Swift 6.0, SwiftUI, AppKit NSPanel, KeyboardShortcuts 2.x, GRDB (via existing ClipboardViewModel), XCTest

---

## File Map

| File | Status | Role |
|---|---|---|
| `ClipboardManager/UI/Drawer/DrawerView.swift` | Modify | Add double-tap gesture to card strip |
| `ClipboardManager/Settings.swift` | Modify | Add `compactMode` key + property |
| `ClipboardManager/Services/HotkeyService.swift` | Modify | Add `toggleCompactPopup` name + callback |
| `ClipboardManager/UI/Compact/CompactPopupGeometry.swift` | Create | Pure positioning math |
| `ClipboardManager/UI/Compact/CompactPopupWindow.swift` | Create | NSPanel subclass |
| `ClipboardManager/UI/Compact/CompactClipboardCard.swift` | Create | 52pt compact row view |
| `ClipboardManager/UI/Compact/CompactPopupView.swift` | Create | Root SwiftUI view (ScrollView of cards) |
| `ClipboardManager/UI/Compact/CompactPopupWindowController.swift` | Create | @MainActor lifecycle controller |
| `ClipboardManager/UI/Preferences/GeneralPane.swift` | Modify | Add compact mode toggle |
| `ClipboardManager/UI/Preferences/ShortcutsPane.swift` | Modify | Add compact popup shortcut recorder |
| `ClipboardManager/App/AppCoordinator.swift` | Modify | Instantiate controller, wire hotkey |
| `ClipboardManagerTests/CompactPopupGeometryTests.swift` | Create | Geometry unit tests |
| `ClipboardManagerTests/SettingsTests.swift` | Modify | Add compactMode tests |
| `ClipboardManagerTests/HotkeyServiceTests.swift` | Modify | Add toggleCompactPopup test |

---

## Task 1: Double-click to paste in DrawerView

**Files:**
- Modify: `ClipboardManager/UI/Drawer/DrawerView.swift`

Context: `DrawerView.cardStrip` renders `ClipboardCard` items. Each card has `.onTapGesture { viewModel.jumpTo(index: idx) }`. SwiftUI resolves multiple tap-count gestures by evaluating higher counts first — so adding `.onTapGesture(count: 2)` before the single-tap gesture makes double-click trigger paste without delaying single-click.

- [ ] **Step 1: Add the double-tap gesture**

In `DrawerView.swift`, find the `.onTapGesture` block inside `cardStrip` and add a `.onTapGesture(count: 2)` immediately before it:

```swift
// Before (existing):
.onTapGesture {
    viewModel.jumpTo(index: idx)
}

// After:
.onTapGesture(count: 2) {
    onPaste?(item, false)
}
.onTapGesture {
    viewModel.jumpTo(index: idx)
}
```

The full updated card block inside `ForEach` should look like:

```swift
ClipboardCard(
    item: item,
    isFocused: idx == viewModel.focusedIndex,
    onPaste: { onPaste?($0, $1) },
    onCopy: { onCopy?($0) },
    onDelete: { onDelete?($0) },
    onOpenURL: { onOpenURL?($0) },
    onRevealInFinder: { onRevealInFinder?($0) }
)
.id(item.id ?? -1)
.onTapGesture(count: 2) {
    onPaste?(item, false)
}
.onTapGesture {
    viewModel.jumpTo(index: idx)
}
.onHover { hovering in
    // ... existing hover code unchanged
}
```

- [ ] **Step 2: Build and verify**

Open the project in Xcode (`open ClipboardManager.xcodeproj`) and build (`⌘B`). Confirm no compiler errors.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerView.swift
git commit -m "feat: double-click on drawer card pastes immediately"
```

---

## Task 2: Add `compactMode` to Settings

**Files:**
- Modify: `ClipboardManager/Settings.swift`
- Modify: `ClipboardManagerTests/SettingsTests.swift`

Context: `Settings` is a thin struct wrapping `UserDefaults`. Each property has a `Key` constant, a getter with a sensible default when the key is absent, and a `nonmutating set`. Pattern to follow: `showHoverPreview` (Bool with true default).

- [ ] **Step 1: Write failing tests**

Add to `ClipboardManagerTests/SettingsTests.swift` inside `final class SettingsTests`:

```swift
func testCompactModeDefaultIsFalse() {
    XCTAssertFalse(Settings(defaults: defaults).compactMode)
}

func testCompactModeRoundtrips() {
    let s = Settings(defaults: defaults)
    s.compactMode = true
    XCTAssertTrue(Settings(defaults: defaults).compactMode)
    s.compactMode = false
    XCTAssertFalse(Settings(defaults: defaults).compactMode)
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -scheme ClipboardManager -only-testing:ClipboardManagerTests/SettingsTests/testCompactModeDefaultIsFalse -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: compile error — `compactMode` is not yet defined.

- [ ] **Step 3: Add key and property to Settings.swift**

In `Settings.Key`, add after `launchAtLogin`:
```swift
static let compactMode = "compactMode"
```

In `struct Settings`, add after `showHoverPreview`:
```swift
var compactMode: Bool {
    get {
        if defaults.object(forKey: Key.compactMode) == nil { return false }
        return defaults.bool(forKey: Key.compactMode)
    }
    nonmutating set { defaults.set(newValue, forKey: Key.compactMode) }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild test -scheme ClipboardManager -only-testing:ClipboardManagerTests/SettingsTests -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all SettingsTests pass.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Settings.swift ClipboardManagerTests/SettingsTests.swift
git commit -m "feat: add compactMode setting"
```

---

## Task 3: Add `toggleCompactPopup` shortcut to HotkeyService

**Files:**
- Modify: `ClipboardManager/Services/HotkeyService.swift`
- Modify: `ClipboardManagerTests/HotkeyServiceTests.swift`

Context: `KeyboardShortcuts.Name` extensions are static lets with an optional `default:` shortcut. `toggleCompactPopup` ships with NO default — the user assigns one in Preferences. `HotkeyService.init` takes one closure per registered shortcut; adding a third parameter `onCompactToggle` follows the existing pattern. `AppCoordinator` (updated in Task 10) is the only call site.

- [ ] **Step 1: Write failing test**

Add to `HotkeyServiceTests`:

```swift
func testCompactPopupShortcutHasNoDefault() {
    XCTAssertNil(
        KeyboardShortcuts.getShortcut(for: .toggleCompactPopup),
        "toggleCompactPopup must ship with no default shortcut — user assigns it in Preferences"
    )
}
```

- [ ] **Step 2: Run test to confirm compile error**

```bash
xcodebuild test -scheme ClipboardManager -only-testing:ClipboardManagerTests/HotkeyServiceTests/testCompactPopupShortcutHasNoDefault -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: compile error — `.toggleCompactPopup` does not exist yet.

- [ ] **Step 3: Add shortcut name and update HotkeyService**

Replace the full content of `ClipboardManager/Services/HotkeyService.swift` with:

```swift
// ClipboardManager/Services/HotkeyService.swift
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that toggles the bottom drawer. Default: ⌘⇧V.
    static let toggleDrawer = Self("toggleDrawer", default: .init(.v, modifiers: [.command, .shift]))

    /// Global shortcut that triggers an interactive screenshot to the
    /// clipboard. The system `screencapture -i -c` tool runs; the resulting
    /// image lands on NSPasteboard.general and is picked up by the monitor
    /// like any other clipboard change. Default: ⌘⇧A.
    static let screenshotToClipboard = Self("screenshotToClipboard", default: .init(.a, modifiers: [.command, .shift]))

    /// Global shortcut that opens the compact cursor-adjacent popup.
    /// Ships with no default — user assigns in Preferences → Shortcuts.
    static let toggleCompactPopup = Self("toggleCompactPopup")
}

@MainActor
final class HotkeyService {
    private let onToggle: @MainActor () -> Void
    private let onScreenshot: @MainActor () -> Void
    private let onCompactToggle: @MainActor () -> Void

    init(
        onToggle: @escaping @MainActor () -> Void,
        onScreenshot: @escaping @MainActor () -> Void,
        onCompactToggle: @escaping @MainActor () -> Void = { @MainActor in }
    ) {
        self.onToggle = onToggle
        self.onScreenshot = onScreenshot
        self.onCompactToggle = onCompactToggle
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleDrawer) { [weak self] in
            Log.hotkey.info("toggleDrawer fired")
            self?.onToggle()
        }
        KeyboardShortcuts.onKeyDown(for: .screenshotToClipboard) { [weak self] in
            Log.hotkey.info("screenshotToClipboard fired")
            self?.onScreenshot()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleCompactPopup) { [weak self] in
            Log.hotkey.info("toggleCompactPopup fired")
            self?.onCompactToggle()
        }
    }

    func stop() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
```

- [ ] **Step 4: Run all hotkey tests**

```bash
xcodebuild test -scheme ClipboardManager -only-testing:ClipboardManagerTests/HotkeyServiceTests -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all 5 HotkeyServiceTests pass (3 existing + 1 new).

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Services/HotkeyService.swift ClipboardManagerTests/HotkeyServiceTests.swift
git commit -m "feat: add toggleCompactPopup shortcut name and HotkeyService callback"
```

---

## Task 4: CompactPopupGeometry (pure positioning helper + tests)

**Files:**
- Create: `ClipboardManager/UI/Compact/CompactPopupGeometry.swift`
- Create: `ClipboardManagerTests/CompactPopupGeometryTests.swift`

Context: All popup positioning math lives here so it can be unit-tested without spinning up any windows. `NSPoint` is `CGPoint` on macOS — same type, no import needed. Screen coordinates on macOS have Y=0 at bottom-left (Quartz/AppKit convention). The popup appears above the cursor: `y = cursor.y + edgeInset`. Clamping keeps the popup fully within the screen's visible frame.

- [ ] **Step 1: Write failing tests**

Create `ClipboardManagerTests/CompactPopupGeometryTests.swift`:

```swift
// ClipboardManagerTests/CompactPopupGeometryTests.swift
import XCTest
@testable import ClipboardManager

final class CompactPopupGeometryTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testWidthIsAlwaysPopupWidth() {
        let f = CompactPopupGeometry.frame(near: NSPoint(x: 720, y: 400), itemCount: 5, in: screen)
        XCTAssertEqual(f.width, CompactPopupGeometry.popupWidth)
    }

    func testPopupAppearsAboveCursor() {
        let cursor = NSPoint(x: 720, y: 400)
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 3, in: screen)
        // Bottom edge of popup is at or above cursor
        XCTAssertGreaterThanOrEqual(f.minY, cursor.y)
    }

    func testCenteredHorizontallyOnCursor() {
        let cursor = NSPoint(x: 720, y: 400)
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 3, in: screen)
        let expectedX = cursor.x - CompactPopupGeometry.popupWidth / 2
        XCTAssertEqual(f.minX, expectedX, accuracy: 0.5)
    }

    func testClampedToLeftEdge() {
        let cursor = NSPoint(x: 5, y: 400) // near left edge
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 1, in: screen)
        XCTAssertGreaterThanOrEqual(f.minX, screen.minX + CompactPopupGeometry.edgeInset - 0.5)
    }

    func testClampedToRightEdge() {
        let cursor = NSPoint(x: 1435, y: 400) // near right edge
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 1, in: screen)
        XCTAssertLessThanOrEqual(f.maxX, screen.maxX - CompactPopupGeometry.edgeInset + 0.5)
    }

    func testClampedToTopEdge() {
        let cursor = NSPoint(x: 720, y: 890) // near top
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 10, in: screen)
        XCTAssertLessThanOrEqual(f.maxY, screen.maxY - CompactPopupGeometry.edgeInset + 0.5)
    }

    func testHeightCappedAtMaxHeight() {
        let f = CompactPopupGeometry.frame(near: NSPoint(x: 720, y: 400), itemCount: 10, in: screen)
        XCTAssertLessThanOrEqual(f.height, CompactPopupGeometry.maxHeight)
    }

    func testZeroItemsProducesMinimumHeight() {
        let f = CompactPopupGeometry.frame(near: NSPoint(x: 720, y: 400), itemCount: 0, in: screen)
        XCTAssertGreaterThan(f.height, 0)
    }

    func testOffsetScreenUsesScreenOrigin() {
        // Screen at non-zero origin (e.g. second monitor)
        let offset = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let cursor = NSPoint(x: 1442, y: 500) // near left edge of this screen
        let f = CompactPopupGeometry.frame(near: cursor, itemCount: 1, in: offset)
        XCTAssertGreaterThanOrEqual(f.minX, offset.minX + CompactPopupGeometry.edgeInset - 0.5)
    }
}
```

- [ ] **Step 2: Run tests to confirm compile error**

```bash
xcodebuild test -scheme ClipboardManager -only-testing:ClipboardManagerTests/CompactPopupGeometryTests -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: compile error — `CompactPopupGeometry` does not exist yet.

- [ ] **Step 3: Create CompactPopupGeometry.swift**

Create `ClipboardManager/UI/Compact/CompactPopupGeometry.swift`:

```swift
// ClipboardManager/UI/Compact/CompactPopupGeometry.swift
import AppKit

enum CompactPopupGeometry {
    static let popupWidth: CGFloat = 300
    static let rowHeight: CGFloat = 52
    static let maxHeight: CGFloat = 420
    static let edgeInset: CGFloat = 8

    /// Returns the window frame for the compact popup positioned near `cursor`
    /// within `screenFrame` (AppKit screen coordinates, Y up from bottom-left).
    static func frame(near cursor: NSPoint, itemCount: Int, in screenFrame: CGRect) -> CGRect {
        let contentHeight = CGFloat(max(1, itemCount)) * rowHeight + 16
        let height = min(maxHeight, contentHeight)

        let x = max(
            screenFrame.minX + edgeInset,
            min(cursor.x - popupWidth / 2, screenFrame.maxX - popupWidth - edgeInset)
        )
        let y = max(
            screenFrame.minY + edgeInset,
            min(cursor.y + edgeInset, screenFrame.maxY - height - edgeInset)
        )
        return CGRect(x: x, y: y, width: popupWidth, height: height)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild test -scheme ClipboardManager -only-testing:ClipboardManagerTests/CompactPopupGeometryTests -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all 9 CompactPopupGeometryTests pass.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/UI/Compact/CompactPopupGeometry.swift ClipboardManagerTests/CompactPopupGeometryTests.swift
git commit -m "feat: CompactPopupGeometry — cursor-relative panel positioning with clamping"
```

---

## Task 5: CompactPopupWindow (NSPanel subclass)

**Files:**
- Create: `ClipboardManager/UI/Compact/CompactPopupWindow.swift`

Context: Mirrors `DrawerWindow` pattern but simpler — no keyboard navigation, just ESC-to-dismiss. Uses `.popUpMenu` level (one step above `.statusBar` used by the drawer) so it appears on top. The generic `<V: View>` init accepts any SwiftUI view via `NSHostingView`.

- [ ] **Step 1: Create CompactPopupWindow.swift**

```swift
// ClipboardManager/UI/Compact/CompactPopupWindow.swift
import AppKit
import SwiftUI

final class CompactPopupWindow: NSPanel {

    init<V: View>(rootView: V) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
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

        let host = NSHostingView(rootView: rootView)
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            orderOut(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
```

- [ ] **Step 2: Build to confirm no errors**

```bash
xcodebuild build -scheme ClipboardManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Compact/CompactPopupWindow.swift
git commit -m "feat: CompactPopupWindow — borderless popUpMenu-level NSPanel"
```

---

## Task 6: CompactClipboardCard (row view)

**Files:**
- Create: `ClipboardManager/UI/Compact/CompactClipboardCard.swift`

Context: A 52pt-tall button-row showing kind icon/thumbnail, truncated label, optional secondary hint, and relative timestamp. Reuses the same `symbolName`/`colorForExtension` logic as `ClipboardCard`. Reads `BlobStore` from the `\.blobStore` environment key (same as `ClipboardCard`). Tapping calls `onPaste(item)`.

- [ ] **Step 1: Create CompactClipboardCard.swift**

```swift
// ClipboardManager/UI/Compact/CompactClipboardCard.swift
import SwiftUI
import AppKit

struct CompactClipboardCard: View {
    let item: Item
    let onPaste: (Item) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.blobStore) private var blobStore
    @State private var isHovered = false

    private var dark: Bool { scheme == .dark }

    var body: some View {
        Button(action: { onPaste(item) }) {
            HStack(spacing: 10) {
                iconView
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLabel)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(dark ? 0.85 : 0.75))
                    if let secondary = secondaryLabel {
                        Text(secondary)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Text(relativeTime(item.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(dark ? 0.3 : 0.25))
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                isHovered
                    ? Color.primary.opacity(dark ? 0.08 : 0.06)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        if item.kind == "image" {
            imageThumb
        } else if item.kind == "file" {
            let ref = try? FileReference.decodingJSON(item.body)
            let ext = ref?.fileExtension ?? ""
            Image(systemName: symbolName(for: ext))
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(colorForExtension(ext))
        } else {
            let symbol: String = {
                if item.subtype == TextSubtype.url.rawValue { return "link" }
                if item.subtype == TextSubtype.code.rawValue || item.subtype == TextSubtype.json.rawValue {
                    return "chevron.left.forwardslash.chevron.right"
                }
                return "doc.text"
            }()
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(DesignColors.accent)
        }
    }

    @ViewBuilder
    private var imageThumb: some View {
        if let path = item.blobPath,
           let blobStore,
           let nsImage = NSImage(contentsOf: blobStore.absoluteURL(forRelativePath: path)) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(DesignColors.accent)
        }
    }

    private var primaryLabel: String {
        if item.kind == "file" {
            return (try? FileReference.decodingJSON(item.body))?.name ?? "File"
        }
        return String(item.body.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var secondaryLabel: String? {
        if item.kind == "image" { return item.dimensions }
        if item.kind == "file" {
            return (try? FileReference.decodingJSON(item.body))?.formattedSize
        }
        if item.subtype == TextSubtype.url.rawValue { return "URL" }
        if item.subtype == TextSubtype.code.rawValue || item.subtype == TextSubtype.json.rawValue { return "Code" }
        return nil
    }

    private func symbolName(for ext: String) -> String {
        switch ext {
        case "pdf":                                             return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "tiff":      return "photo"
        case "mp4", "mov", "m4v":                              return "film"
        case "mp3", "wav", "m4a", "aiff":                     return "music.note"
        case "zip", "tar", "gz", "7z":                        return "doc.zipper"
        case "fig":                                            return "paintbrush"
        case "sketch":                                         return "scribble"
        case "key", "pages", "numbers":                       return "doc.text"
        case "xlsx", "csv":                                    return "tablecells"
        case "docx", "rtf", "txt", "md":                      return "doc.text"
        default:                                               return "doc"
        }
    }

    private func colorForExtension(_ ext: String) -> Color {
        switch ext {
        case "pdf":                                            return .red
        case "fig":                                            return .purple
        case "sketch":                                         return .orange
        case "key":                                            return .blue
        case "xlsx", "csv":                                    return .green
        case "docx":                                           return .blue
        case "zip", "tar", "gz", "7z":                        return .gray
        case "png", "jpg", "jpeg", "gif", "heic", "tiff":     return .pink
        case "mp4", "mov", "m4v":                             return .purple
        default:                                               return .secondary
        }
    }

    private func relativeTime(_ epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Text item") {
    let item = Item(
        id: 1, kind: "text", subtype: "plain", contentHash: "a",
        body: "Hello world — this is a clipboard item",
        blobPath: nil, dimensions: nil, byteSize: 50,
        sourceApp: "Safari", sourceBundleId: nil,
        createdAt: Int64(Date().timeIntervalSince1970) - 90,
        pinned: false, snippetId: nil, deletedAt: nil
    )
    return CompactClipboardCard(item: item, onPaste: { _ in })
        .frame(width: 300)
        .preferredColorScheme(.dark)
}

#Preview("URL item") {
    let item = Item(
        id: 2, kind: "text", subtype: TextSubtype.url.rawValue, contentHash: "b",
        body: "https://apple.com/swift",
        blobPath: nil, dimensions: nil, byteSize: 30,
        sourceApp: "Chrome", sourceBundleId: nil,
        createdAt: Int64(Date().timeIntervalSince1970) - 300,
        pinned: false, snippetId: nil, deletedAt: nil
    )
    return CompactClipboardCard(item: item, onPaste: { _ in })
        .frame(width: 300)
        .preferredColorScheme(.light)
}
```

- [ ] **Step 2: Build to confirm no errors**

```bash
xcodebuild build -scheme ClipboardManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Compact/CompactClipboardCard.swift
git commit -m "feat: CompactClipboardCard — 52pt compact row with icon, label, timestamp"
```

---

## Task 7: CompactPopupView (root SwiftUI view)

**Files:**
- Create: `ClipboardManager/UI/Compact/CompactPopupView.swift`

Context: Root view for the compact popup window. Reads the 10 most recent items directly from `ClipboardViewModel` via `@ObservedObject` so it always shows fresh data without needing to be recreated. Visual language matches the drawer: `VisualEffectBackground` + linear gradient overlay + 12pt rounded corners + hairline border.

- [ ] **Step 1: Create CompactPopupView.swift**

```swift
// ClipboardManager/UI/Compact/CompactPopupView.swift
import SwiftUI

struct CompactPopupView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let onPaste: (Item) -> Void
    let blobStore: BlobStore?

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var items: [Item] {
        Array(viewModel.items.prefix(10))
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: DesignMaterials.drawer(dark: dark))

            LinearGradient(
                colors: dark
                    ? [Color(red: 52/255, green: 52/255, blue: 56/255).opacity(0.97),
                       Color(red: 32/255, green: 32/255, blue: 35/255).opacity(0.99)]
                    : [Color(red: 248/255, green: 248/255, blue: 252/255).opacity(0.97),
                       Color(red: 240/255, green: 240/255, blue: 245/255).opacity(0.99)],
                startPoint: .top, endPoint: .bottom
            )

            if items.isEmpty {
                Text("No items yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(dark ? 0.3 : 0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            CompactClipboardCard(item: item, onPaste: onPaste)
                            if idx < items.count - 1 {
                                Rectangle()
                                    .fill(DesignColors.hairline(dark: dark))
                                    .frame(height: 0.5)
                                    .padding(.leading, 50)
                            }
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
        .ignoresSafeArea()
        .environment(\.blobStore, blobStore)
    }
}

#Preview {
    let store = try! ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    let vm = ClipboardViewModel(store: store)
    return CompactPopupView(viewModel: vm, onPaste: { _ in }, blobStore: nil)
        .frame(width: 300, height: 300)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build to confirm no errors**

```bash
xcodebuild build -scheme ClipboardManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Compact/CompactPopupView.swift
git commit -m "feat: CompactPopupView — scrollable list of compact cards with drawer visual style"
```

---

## Task 8: CompactPopupWindowController

**Files:**
- Create: `ClipboardManager/UI/Compact/CompactPopupWindowController.swift`

Context: Mirrors `DrawerWindowController`. Owns a `CompactPopupWindow`, manages show/hide lifecycle, global click-outside monitor, and paste handling (same logic as `DrawerWindowController.handlePaste`). `show(near:)` computes the frame using `CompactPopupGeometry`, then orders front and makes key. `toggle(near:)` is what `AppCoordinator` calls from the hotkey.

- [ ] **Step 1: Create CompactPopupWindowController.swift**

```swift
// ClipboardManager/UI/Compact/CompactPopupWindowController.swift
import AppKit

@MainActor
final class CompactPopupWindowController {
    private let window: CompactPopupWindow
    private let viewModel: ClipboardViewModel
    private let injector: PasteInjector
    private let store: ClipboardStore
    private(set) var isVisible: Bool = false
    private var clickOutsideMonitor: Any?

    init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore, injector: PasteInjector) {
        self.viewModel = viewModel
        self.injector = injector
        self.store = store

        var pasteHandler: ((Item) -> Void)!

        self.window = CompactPopupWindow(
            rootView: CompactPopupView(
                viewModel: viewModel,
                onPaste: { item in pasteHandler(item) },
                blobStore: blobStore
            )
        )

        pasteHandler = { [weak self] item in self?.handlePaste(item: item) }
    }

    func toggle(near cursor: NSPoint) {
        isVisible ? hide() : show(near: cursor)
    }

    func show(near cursor: NSPoint) {
        guard !isVisible else { return }
        let itemCount = min(10, viewModel.items.count)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
                     ?? NSScreen.main
                     ?? NSScreen.screens[0]
        let frame = CompactPopupGeometry.frame(near: cursor, itemCount: itemCount, in: screen.visibleFrame)

        window.setFrame(frame, display: false)
        window.orderFrontRegardless()
        window.makeKey()
        isVisible = true

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible else { return }
                if !self.window.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        window.orderOut(nil)
        isVisible = false
    }

    private func handlePaste(item: Item) {
        do {
            try injector.writeToPasteboard(item: item, asPlainText: false)
        } catch {
            Log.drawer.error("compact paste write failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        hide()
        guard injector.hasAccessibilityPermission else {
            Log.drawer.info("compact paste skipped — Accessibility permission missing")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.injector.synthesizePasteKeystroke()
        }
    }
}
```

- [ ] **Step 2: Build to confirm no errors**

```bash
xcodebuild build -scheme ClipboardManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Compact/CompactPopupWindowController.swift
git commit -m "feat: CompactPopupWindowController — show/hide/toggle near cursor with paste handling"
```

---

## Task 9: Preferences UI (GeneralPane + ShortcutsPane)

**Files:**
- Modify: `ClipboardManager/UI/Preferences/GeneralPane.swift`
- Modify: `ClipboardManager/UI/Preferences/ShortcutsPane.swift`

Context: `GeneralPane` uses `@AppStorage` bindings and a macOS `Form` with grouped sections. Add a compact mode toggle in the existing "Drawer" section, below the hover preview toggle. `ShortcutsPane` adds a `KeyboardShortcuts.Recorder` row in a new "Compact Mode" section, or in the existing "Global Hotkeys" section.

- [ ] **Step 1: Update GeneralPane.swift**

Add `@AppStorage` for `compactMode` and add the toggle in the "Drawer" section:

```swift
// ClipboardManager/UI/Preferences/GeneralPane.swift
import SwiftUI

struct GeneralPane: View {
    @AppStorage(Settings.Key.appearance) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(Settings.Key.historyLimit) private var historyLimit: Int = 5000
    @AppStorage(Settings.Key.retentionDays) private var retentionDays: Int = 90
    @AppStorage(Settings.Key.showHoverPreview) private var showHoverPreview: Bool = true
    @AppStorage(Settings.Key.compactMode) private var compactMode: Bool = false

    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at Login")
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        try LaunchAtLogin.setEnabled(newValue)
                    } catch {
                        Log.app.error("launch at login toggle failed: \(error.localizedDescription, privacy: .public)")
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { a in
                        Text(a.label).tag(a.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("History") {
                Picker("Max items", selection: $historyLimit) {
                    Text("500").tag(500)
                    Text("1,000").tag(1000)
                    Text("5,000").tag(5000)
                    Text("10,000").tag(10000)
                    Text("Unlimited").tag(Int.max)
                }
                Picker("Keep for", selection: $retentionDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(Int.max)
                }
            }

            Section("Drawer") {
                Toggle(isOn: $showHoverPreview) {
                    Text("Show preview on hover")
                }
                Toggle(isOn: $compactMode) {
                    Text("Compact Mode")
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    GeneralPane()
        .frame(width: 400, height: 500)
}
```

- [ ] **Step 2: Update ShortcutsPane.swift**

Add a "Compact Mode" section with the recorder for `toggleCompactPopup`:

```swift
// ClipboardManager/UI/Preferences/ShortcutsPane.swift
import SwiftUI
import KeyboardShortcuts

struct ShortcutsPane: View {
    var body: some View {
        Form {
            Section("Global Hotkeys") {
                KeyboardShortcuts.Recorder("Toggle Clipboard Drawer", name: .toggleDrawer)
                KeyboardShortcuts.Recorder("Screenshot Region to Clipboard", name: .screenshotToClipboard)
            }

            Section("Compact Mode") {
                KeyboardShortcuts.Recorder("Open Compact Popup", name: .toggleCompactPopup)
            }

            Section {
                Text("Click a shortcut and press the keys you want. Click the × to clear.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ShortcutsPane()
        .frame(width: 400, height: 300)
}
```

- [ ] **Step 3: Build to confirm no errors**

```bash
xcodebuild build -scheme ClipboardManager -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ClipboardManager/UI/Preferences/GeneralPane.swift ClipboardManager/UI/Preferences/ShortcutsPane.swift
git commit -m "feat: compact mode toggle in General pane, shortcut recorder in Shortcuts pane"
```

---

## Task 10: Wire AppCoordinator

**Files:**
- Modify: `ClipboardManager/App/AppCoordinator.swift`

Context: `AppCoordinator.init` constructs all services and wires callbacks. Add `CompactPopupWindowController` as a stored property, initialize it after `viewModel` and `injector` are ready, and pass `onCompactToggle` to `HotkeyService`. `HotkeyService.init` now requires three closures (added in Task 3). The compact popup `toggle(near:)` needs `NSEvent.mouseLocation` at the time the hotkey fires — that happens inside the `@MainActor` closure so it's safe.

- [ ] **Step 1: Update AppCoordinator.swift**

Replace the full content with:

```swift
// ClipboardManager/App/AppCoordinator.swift
import AppKit

@MainActor
final class AppCoordinator {
    private let store: ClipboardStore
    private let blobStore: BlobStore
    private let viewModel: ClipboardViewModel
    private let menuBar: MenuBarController
    private let drawer: DrawerWindowController
    private let compactPopup: CompactPopupWindowController
    private let hotkey: HotkeyService
    private let monitor: PasteboardMonitor
    private let retention: RetentionJob
    private let pasteInjector: PasteInjector
    private let preferencesWindow = PreferencesWindowController()

    init() throws {
        let store = try ClipboardStore()
        try store.seedDefaultExclusionsIfNeeded()
        self.store = store

        let blobStore = try BlobStore()
        self.blobStore = blobStore

        let injector = PasteInjector(blobStore: blobStore)
        self.pasteInjector = injector

        let viewModel = ClipboardViewModel(store: store)
        self.viewModel = viewModel

        let drawer = DrawerWindowController(viewModel: viewModel, blobStore: blobStore, store: store, injector: injector)
        self.drawer = drawer

        let compact = CompactPopupWindowController(viewModel: viewModel, blobStore: blobStore, store: store, injector: injector)
        self.compactPopup = compact

        let prefs = self.preferencesWindow
        self.menuBar = MenuBarController(
            onOpenClipboard: { drawer.toggle() },
            onOpenPreferences: { prefs.show() }
        )
        self.hotkey = HotkeyService(
            onToggle: { drawer.toggle() },
            onScreenshot: { AppCoordinator.captureScreenshotToClipboard() },
            onCompactToggle: { compact.toggle(near: NSEvent.mouseLocation) }
        )
        self.monitor = PasteboardMonitor(store: store, blobStore: blobStore)
        self.retention = RetentionJob(store: store)
    }

    func start() {
        applyAppearance()
        Log.coordinator.info("coordinator starting")
        hotkey.start()
        monitor.start()
        retention.start()

        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyAppearance() }
        }
    }

    private func applyAppearance() {
        let appearance = Settings().appearance
        NSApp.appearance = appearance.nsAppearance
    }

    /// Spawns `screencapture -i -c` so the user can drag-select a region;
    /// the resulting image lands on NSPasteboard and the monitor picks it up.
    static func captureScreenshotToClipboard() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-c"]
        do {
            try task.run()
            Log.coordinator.info("screencapture -i -c launched")
        } catch {
            Log.coordinator.error("screencapture launch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

- [ ] **Step 2: Run full test suite**

```bash
xcodebuild test -scheme ClipboardManager -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: all tests pass, `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/App/AppCoordinator.swift
git commit -m "wire: CompactPopupWindowController wired into AppCoordinator and HotkeyService"
```

---

## Smoke Test Checklist

After all tasks complete, run the app and verify:

1. **Double-click**: Open drawer (`⌘⇧V`), double-click any card → item pastes into foreground app, drawer closes.
2. **Single-click still works**: Single-click a card in the drawer → card is selected (focus ring), no paste.
3. **Compact popup**: Enable compact mode in Preferences → General → Drawer section. Assign a shortcut in Preferences → Shortcuts → "Open Compact Popup". Press shortcut → popup appears near cursor showing ≤10 recent items.
4. **Compact paste**: Click any item in the compact popup → paste fires, popup dismisses.
5. **Compact dismiss**: Open compact popup, click outside → dismisses. Open again, press ESC → dismisses.
6. **Compact empty state**: Clear all history, open compact popup → "No items yet" message shown.
7. **No default shortcut**: Confirm `toggleCompactPopup` has no shortcut assigned by default in Preferences → Shortcuts.
8. **Settings persist**: Toggle compact mode off/on, relaunch app → setting persists.
