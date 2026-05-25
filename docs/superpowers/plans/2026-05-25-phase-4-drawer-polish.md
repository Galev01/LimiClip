# Clipboard Manager — Phase 4 Implementation Plan (Drawer Polish)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the bare card strip into the productive drawer the design promises. Tabs filter by kind. Search filters by substring. Arrow keys / `⌘1-9` move focus, Enter pastes the focused card into the previously-active app, Esc dismisses, `⌫` deletes. Right-click a card for a context menu of quick actions. Hovering for 400 ms reveals a full-content preview popover.

**Architecture additions:**
- The `ClipboardViewModel` becomes the single source of truth for `selectedTab`, `searchQuery`, `focusedIndex`, and the derived `filteredItems`. The drawer becomes a thin view over its state.
- `PasteInjector` is a new `@MainActor` service that:
  - Writes a clipboard item back to `NSPasteboard.general` (text / image data / file URL — kind-aware).
  - Synthesises a Cmd-V keystroke via `CGEvent.post` into whatever app is frontmost after the drawer dismisses.
  - Best-effort: if Accessibility permission is missing, the pasteboard write still succeeds and the user can paste manually with `⌘V`. The system Accessibility prompt is shown the first time we try to post events.
- `DrawerWindowController` tracks the **previously-active app** at `show()` time so paste-injection can route the keystroke back to it (in practice, our `.nonactivatingPanel` means the previous app remains frontmost; we record it as a safety net).
- A new `HoverPreviewPanel` (a borderless `NSPanel` floating above the drawer) renders a full-content preview after a 400 ms hover. Closing on mouse-leave is debounced.

**Verification target at end of Phase 4:**
- Switching tabs (All/Text/Images/Files/Pinned) filters the strip.
- Typing in the search box filters cards live with matched substrings highlighted in plain-text cards.
- `←`/`→` move a glowing blue focus border between cards; `⌘1-9` jumps to card N.
- `Enter` on a focused text card → drawer slides out → the card's text is pasted into the app you were just using.
- `Enter` on an image card → image is on the clipboard and `⌘V` pastes it into the destination app.
- Right-click a card → context menu with "Paste", "Paste as Plain Text", "Copy", "Open URL" (for URLs), "Reveal in Finder" (for files), "Delete".
- Hovering for ~400 ms → a popover above the card shows the full text / full image / full file metadata.

---

## File Structure (this phase)

```
ClipboardManager/
├── ClipboardViewModel.swift              (MODIFIED — selectedTab + searchQuery + focusedIndex + filteredItems)
├── Services/
│   └── PasteInjector.swift               (NEW)
├── UI/Drawer/
│   ├── DrawerTabBar.swift                (NEW)
│   ├── DrawerSearch.swift                (NEW)
│   ├── DrawerHoverPreview.swift          (NEW — NSPanel-backed)
│   ├── ClipboardCard.swift               (MODIFIED — isFocused state, hover/right-click actions)
│   ├── DrawerView.swift                  (MODIFIED — top bar, bottom hint bar, card click handlers)
│   ├── DrawerWindow.swift                (MODIFIED — arrow/Enter/⌘1-9/⌫ handling, captures frontmost)
│   └── DrawerWindowController.swift      (MODIFIED — owns PasteInjector + HoverPreview window)
└── App/
    └── AppCoordinator.swift              (MODIFIED — wires PasteInjector)

ClipboardManagerTests/
├── ClipboardViewModelTests.swift         (NEW — selection + filtering logic)
└── PasteInjectorTests.swift              (NEW — pasteboard write paths)
```

---

## Pre-flight

```bash
cd /Users/gal.lev/Clipboard
git log --oneline -1   # should be 2e29200
git tag -l             # should include v0.3.0-phase3, v0.3.1
make test 2>&1 | tail -3
```

Expected: 54 tests pass.

---

## Task 1: ClipboardViewModel — tab + search + focus (TDD)

The view model takes over filtering. Tests use a real ClipboardStore (in-memory, fast) and exercise the published state transitions.

**Files:**
- Modify: `ClipboardManager/ClipboardViewModel.swift`
- Create: `ClipboardManagerTests/ClipboardViewModelTests.swift`

- [ ] **Step 1: Failing tests**

`/Users/gal.lev/Clipboard/ClipboardManagerTests/ClipboardViewModelTests.swift`:

```swift
import XCTest
@testable import ClipboardManager

@MainActor
final class ClipboardViewModelTests: XCTestCase {

    private func makeStore() throws -> ClipboardStore {
        try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    }

    func testFilteredItemsIncludesAllByDefault() throws {
        let store = try makeStore()
        _ = try store.recordText("hello", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("world", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        XCTAssertEqual(vm.filteredItems.count, 2)
        XCTAssertEqual(vm.selectedTab, .all)
    }

    func testTabFiltersByKind() throws {
        let store = try makeStore()
        _ = try store.recordText("text item", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordImage(
            contentHash: "img-hash", blobPath: "aa/bb/x.png",
            dimensions: .init(width: 10, height: 10), byteSize: 100,
            sourceApp: nil, sourceBundleId: nil
        )
        let ref = FileReference(path: "/x/y.pdf", name: "y.pdf", byteSize: 1, modifiedAt: 1)
        _ = try store.recordFile(reference: ref, sourceApp: nil, sourceBundleId: nil)

        let vm = ClipboardViewModel(store: store)

        vm.selectedTab = .text
        XCTAssertEqual(vm.filteredItems.map(\.body), ["text item"])

        vm.selectedTab = .images
        XCTAssertEqual(vm.filteredItems.first?.kind, "image")
        XCTAssertEqual(vm.filteredItems.count, 1)

        vm.selectedTab = .files
        XCTAssertEqual(vm.filteredItems.first?.kind, "file")
        XCTAssertEqual(vm.filteredItems.count, 1)

        vm.selectedTab = .all
        XCTAssertEqual(vm.filteredItems.count, 3)
    }

    func testPinnedTabIsEmptyForNowButSelectable() throws {
        // Phase 5 wires snippets; Phase 4 just makes sure the tab is selectable
        // without crashing.
        let store = try makeStore()
        _ = try store.recordText("not pinned", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        vm.selectedTab = .pinned
        XCTAssertEqual(vm.filteredItems.count, 0)
    }

    func testSearchFiltersAcrossFields() throws {
        let store = try makeStore()
        _ = try store.recordText("Hello World", sourceApp: "Messages", sourceBundleId: nil)
        _ = try store.recordText("greetings, friend", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        vm.searchQuery = "hello"
        XCTAssertEqual(vm.filteredItems.map(\.body), ["Hello World"])
        vm.searchQuery = "FRIEND"
        XCTAssertEqual(vm.filteredItems.count, 1)
        vm.searchQuery = ""
        XCTAssertEqual(vm.filteredItems.count, 2)
    }

    func testFocusedIndexClampsToBounds() throws {
        let store = try makeStore()
        _ = try store.recordText("one", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("two", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("three", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        XCTAssertEqual(vm.focusedIndex, 0)
        vm.moveFocus(by: +1)
        XCTAssertEqual(vm.focusedIndex, 1)
        vm.moveFocus(by: +10)
        XCTAssertEqual(vm.focusedIndex, 2)
        vm.moveFocus(by: -100)
        XCTAssertEqual(vm.focusedIndex, 0)
    }

    func testJumpToIndexClampsAndIgnoresOutOfRange() throws {
        let store = try makeStore()
        _ = try store.recordText("a", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("b", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        vm.jumpTo(index: 5)
        XCTAssertEqual(vm.focusedIndex, 1)
        vm.jumpTo(index: -3)
        XCTAssertEqual(vm.focusedIndex, 0)
    }

    func testTabOrSearchChangeResetsFocus() throws {
        let store = try makeStore()
        _ = try store.recordText("x", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("y", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        vm.moveFocus(by: 1)
        XCTAssertEqual(vm.focusedIndex, 1)
        vm.selectedTab = .text
        XCTAssertEqual(vm.focusedIndex, 0)
        vm.moveFocus(by: 1)
        vm.searchQuery = "x"
        XCTAssertEqual(vm.focusedIndex, 0)
    }

    func testCurrentItemReturnsFocusedOrNil() throws {
        let store = try makeStore()
        _ = try store.recordText("alpha", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("beta", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        XCTAssertEqual(vm.currentItem?.body, "beta")  // newest first
        vm.moveFocus(by: 1)
        XCTAssertEqual(vm.currentItem?.body, "alpha")
        vm.searchQuery = "zzz"
        XCTAssertNil(vm.currentItem)
    }
}
```

- [ ] **Step 2: Verify build fails** with errors like `Type 'DrawerTab' missing`, `Property 'selectedTab' missing`, etc.

```bash
cd /Users/gal.lev/Clipboard
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | tail -10
```

- [ ] **Step 3: Replace ClipboardViewModel.swift entirely**

```swift
// ClipboardManager/ClipboardViewModel.swift
import Foundation
import Combine

enum DrawerTab: String, CaseIterable, Identifiable, Sendable {
    case all, text, images, files, pinned
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .images: return "Images"
        case .files: return "Files"
        case .pinned: return "Pinned"
        }
    }
}

@MainActor
final class ClipboardViewModel: ObservableObject {

    @Published private(set) var items: [Item] = []
    @Published var selectedTab: DrawerTab = .all {
        didSet { focusedIndex = 0 }
    }
    @Published var searchQuery: String = "" {
        didSet { focusedIndex = 0 }
    }
    @Published private(set) var focusedIndex: Int = 0

    private let store: ClipboardStore
    private let visibleLimit: Int
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init(store: ClipboardStore, visibleLimit: Int = 200) {
        self.store = store
        self.visibleLimit = visibleLimit
        observer = NotificationCenter.default.addObserver(
            forName: .clipboardStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func reload() {
        do {
            items = try store.recentItems(limit: visibleLimit)
        } catch {
            Log.app.error("view model reload failed: \(error.localizedDescription, privacy: .public)")
            items = []
        }
        focusedIndex = min(focusedIndex, max(0, filteredItems.count - 1))
    }

    var filteredItems: [Item] {
        var list = items
        switch selectedTab {
        case .all:    break
        case .text:   list = list.filter { $0.kind == "text" }
        case .images: list = list.filter { $0.kind == "image" }
        case .files:  list = list.filter { $0.kind == "file" }
        case .pinned: list = list.filter { $0.pinned }   // empty in Phase 4
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { item in
                let bag = [item.body, item.sourceApp ?? ""].joined(separator: " ").lowercased()
                return bag.contains(q)
            }
        }
        return list
    }

    var currentItem: Item? {
        let list = filteredItems
        guard !list.isEmpty, focusedIndex < list.count, focusedIndex >= 0 else { return nil }
        return list[focusedIndex]
    }

    func moveFocus(by delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { focusedIndex = 0; return }
        focusedIndex = max(0, min(count - 1, focusedIndex + delta))
    }

    func jumpTo(index: Int) {
        let count = filteredItems.count
        guard count > 0 else { focusedIndex = 0; return }
        focusedIndex = max(0, min(count - 1, index))
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

Expected: 62 tests (54 + 8 new).

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/ClipboardViewModel.swift ClipboardManagerTests/ClipboardViewModelTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "vm: tabs + search + focus state with tests"
```

---

## Task 2: DrawerTabBar SwiftUI view

**Files:**
- Create: `ClipboardManager/UI/Drawer/DrawerTabBar.swift`

- [ ] **Step 1: Implement**

```swift
// ClipboardManager/UI/Drawer/DrawerTabBar.swift
import SwiftUI

struct DrawerTabBar: View {
    @Binding var selectedTab: DrawerTab
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DrawerTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.label)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .foregroundStyle(
                            selectedTab == tab
                                ? .primary.opacity(dark ? 0.95 : 0.85)
                                : .primary.opacity(dark ? 0.45 : 0.4)
                        )
                        .background(
                            selectedTab == tab
                                ? Color.primary.opacity(dark ? 0.12 : 0.08)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.init(tab.label.first!), modifiers: [])
                    .opacity(0)   // hidden keyboard accelerator
                    .frame(width: 0, height: 0)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(dark ? 0.06 : 0.04))
        )
    }
}

#Preview {
    @Previewable @State var tab: DrawerTab = .all
    return DrawerTabBar(selectedTab: $tab)
        .padding()
        .preferredColorScheme(.dark)
}
```

Note on the keyboard accelerator: the `.keyboardShortcut(.init(tab.label.first!))` with `.opacity(0)` lines are intentionally hidden — they reserve the first-letter shortcuts (A/T/I/F/P) without showing visible accelerator UI. **If this produces a compiler warning or layout issue, simply delete those two lines** — Phase 4 keyboard navigation works via Tab/⌘1-9 in the drawer window's keyDown handler, not via SwiftUI keyboardShortcut. Don't fight the compiler on this — strip the shortcut binding if it's flaky.

- [ ] **Step 2: Build**

```bash
make build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerTabBar.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "ui: DrawerTabBar (All/Text/Images/Files/Pinned)"
```

---

## Task 3: DrawerSearch SwiftUI view

**Files:**
- Create: `ClipboardManager/UI/Drawer/DrawerSearch.swift`

- [ ] **Step 1: Implement**

```swift
// ClipboardManager/UI/Drawer/DrawerSearch.swift
import SwiftUI

struct DrawerSearch: View {
    @Binding var query: String
    @Binding var expanded: Bool

    @FocusState private var fieldFocused: Bool
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(dark ? 0.4 : 0.35))

            if expanded {
                TextField("Search clipboard…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($fieldFocused)
                    .onSubmit { /* no-op: search filters live */ }
                    .onExitCommand {
                        query = ""
                        expanded = false
                        fieldFocused = false
                    }
                    .onChange(of: expanded) { _, isOn in
                        fieldFocused = isOn
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(dark ? 0.4 : 0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(width: expanded ? 220 : 32, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(dark ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(expanded
                    ? Color.primary.opacity(dark ? 0.15 : 0.1)
                    : Color.clear,
                    lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !expanded { expanded = true }
        }
        .animation(.easeOut(duration: 0.2), value: expanded)
        .onAppear {
            if expanded { fieldFocused = true }
        }
    }
}

#Preview {
    @Previewable @State var q = ""
    @Previewable @State var expanded = true
    return DrawerSearch(query: $q, expanded: $expanded)
        .padding()
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build**

```bash
make build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerSearch.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "ui: DrawerSearch field (expandable, esc clears)"
```

---

## Task 4: Wire DrawerView with top bar + bottom hint bar + focused-card binding

**Files:**
- Modify: `ClipboardManager/UI/Drawer/DrawerView.swift`
- Modify: `ClipboardManager/UI/Drawer/ClipboardCard.swift` (add `isFocused` prop)

- [ ] **Step 1: Add `isFocused` parameter to ClipboardCard**

Edit `/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/ClipboardCard.swift`. Add `var isFocused: Bool = false` as a property. Update the outermost `.overlay(...)` border so a focused card gets a 2px accent stroke:

Replace:

```swift
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
```

with:

```swift
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused
                        ? DesignColors.accent
                        : DesignColors.hairline(dark: dark),
                    lineWidth: isFocused ? 2 : 0.5
                )
        )
        .shadow(color: isFocused
                    ? DesignColors.accent.opacity(0.25)
                    : Color.clear,
                radius: 12, y: 4)
```

Don't change anything else in the file.

- [ ] **Step 2: Replace DrawerView.swift**

```swift
// ClipboardManager/UI/Drawer/DrawerView.swift
import SwiftUI

struct DrawerView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let blobStore: BlobStore?

    @State private var searchExpanded: Bool = false

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

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

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if viewModel.filteredItems.isEmpty {
                    if viewModel.items.isEmpty && viewModel.searchQuery.isEmpty && viewModel.selectedTab == .all {
                        EmptyStateView()
                    } else {
                        Text(viewModel.searchQuery.isEmpty
                             ? "No items in this tab"
                             : "No results for \"\(viewModel.searchQuery)\"")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(dark ? 0.3 : 0.25))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    cardStrip
                }
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
        .environment(\.blobStore, blobStore)
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            DrawerSearch(query: $viewModel.searchQuery, expanded: $searchExpanded)
            Spacer(minLength: 16)
            DrawerTabBar(selectedTab: $viewModel.selectedTab)
            Spacer(minLength: 16)
            kbdHint
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var kbdHint: some View {
        HStack(spacing: 4) {
            Text("⌘⇧V")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(dark ? 0.08 : 0.05))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(dark ? 0.08 : 0.06), lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("toggle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(dark ? 0.25 : 0.2))
        }
    }

    private var cardStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { idx, item in
                        ClipboardCard(item: item, isFocused: idx == viewModel.focusedIndex)
                            .id(item.id ?? -1)
                            .onTapGesture {
                                viewModel.jumpTo(index: idx)
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.focusedIndex) { _, newIndex in
                let list = viewModel.filteredItems
                guard list.indices.contains(newIndex), let id = list[newIndex].id else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            let count = viewModel.filteredItems.count
            let total = viewModel.items.count
            Text(viewModel.searchQuery.isEmpty
                 ? "\(count) item\(count == 1 ? "" : "s")"
                 : "\(count) of \(total) matched")
            Spacer()
            Text("⏎ paste · ⌫ delete · / search")
        }
        .font(.system(size: 11))
        .foregroundStyle(.primary.opacity(dark ? 0.2 : 0.18))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}

#Preview {
    let store = try! ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    let vm = ClipboardViewModel(store: store)
    return DrawerView(viewModel: vm, blobStore: nil)
        .frame(width: 1440, height: 300)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 3: Build + test**

```bash
make test 2>&1 | tail -8
```

Expected: 62 tests still pass.

- [ ] **Step 4: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerView.swift ClipboardManager/UI/Drawer/ClipboardCard.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "ui: drawer top bar (search/tabs/hint), bottom hint bar, focused border"
```

---

## Task 5: Keyboard navigation in DrawerWindow

**Files:**
- Modify: `ClipboardManager/UI/Drawer/DrawerWindow.swift`

The window's `keyDown` already handles Esc. Extend it for arrow keys, `⌘1-9`, Tab, `⌫`, `/`, and Enter. Enter routing to PasteInjector comes in Task 7 — Phase 4 Task 5 just changes focus + delete.

- [ ] **Step 1: Read current file** at `/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/DrawerWindow.swift`. The window currently has a stored `viewModel` parameter and routes Esc via a notification. We extend it.

The current `init` body sets up the `NSHostingView` and stores nothing referenceable. We need the window to know about the view model so it can call `moveFocus / jumpTo / softDelete`.

Modify the class so the view model is stored:

```swift
final class DrawerWindow: NSPanel {
    static let drawerHeight: CGFloat = 300

    private let viewModel: ClipboardViewModel
    private let store: ClipboardStore   // for soft-delete

    init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore) {
        self.viewModel = viewModel
        self.store = store
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // ... ALL the existing flag setup unchanged ...

        let host = NSHostingView(rootView: DrawerView(viewModel: viewModel, blobStore: blobStore))
        // ... rest of container/constraint setup unchanged ...
    }

    // existing canBecomeKey / canBecomeMain / acceptsFirstResponder unchanged

    override func keyDown(with event: NSEvent) {
        // Allow text-field events (search) to pass through when the field is first responder.
        // SwiftUI's TextField handles its own keystrokes when focused, so unmatched keys
        // come back here.

        let isCommand = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 53:   // Esc
            NotificationCenter.default.post(name: .drawerDismissRequested, object: nil)
        case 123:  // Left
            Task { @MainActor in viewModel.moveFocus(by: -1) }
        case 124:  // Right
            Task { @MainActor in viewModel.moveFocus(by: +1) }
        case 117, 51:  // forward delete, delete
            if let id = viewModel.currentItem?.id {
                Task { @MainActor in
                    do { try store.softDelete(itemId: id) } catch { Log.drawer.error("delete failed") }
                }
            }
        case 18...26 where isCommand:
            // ⌘1 = keyCode 18, ⌘2 = 19, ... ⌘9 = 25, ⌘0 = 29.
            let n = Int(event.keyCode) - 18
            Task { @MainActor in viewModel.jumpTo(index: n) }
        default:
            super.keyDown(with: event)
        }
    }
}

extension Notification.Name {
    static let drawerDismissRequested = Notification.Name("DrawerDismissRequested")
}
```

The store dependency is new — it's how we soft-delete focused items.

- [ ] **Step 2: Update DrawerWindowController to pass the store**

Edit `/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/DrawerWindowController.swift`. Add `store: ClipboardStore` to the init and pass it through to `DrawerWindow`:

```swift
    init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore) {
        self.window = DrawerWindow(viewModel: viewModel, blobStore: blobStore, store: store)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDismissRequest),
            name: .drawerDismissRequested, object: nil
        )
    }
```

Don't change show()/hide() bodies.

- [ ] **Step 3: Update AppCoordinator**

Edit `/Users/gal.lev/Clipboard/ClipboardManager/App/AppCoordinator.swift`. Change the drawer construction line:

```swift
        let drawer = DrawerWindowController(viewModel: viewModel, blobStore: blobStore, store: store)
```

- [ ] **Step 4: Build + test**

```bash
make test 2>&1 | tail -10
```

Expected: 62 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerWindow.swift ClipboardManager/UI/Drawer/DrawerWindowController.swift ClipboardManager/App/AppCoordinator.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "drawer: keyboard nav (arrows, ⌘1-9, ⌫ delete)"
```

---

## Task 6: PasteInjector service (TDD)

**Files:**
- Create: `ClipboardManager/Services/PasteInjector.swift`
- Create: `ClipboardManagerTests/PasteInjectorTests.swift`

The service has two responsibilities:
1. Write an `Item` to a pasteboard (the production case uses `.general`; tests use `withUniqueName()`).
2. Synthesise `⌘V` via `CGEvent.post` to the system event tap.

Only #1 is unit-testable. #2 is integration-level and gated on Accessibility permission; we expose `synthesizePasteKeystroke()` as a separate method that always succeeds at the API level (the OS silently drops it without permission), so we can wire it to a flag for tests.

- [ ] **Step 1: Failing tests**

```swift
// ClipboardManagerTests/PasteInjectorTests.swift
import XCTest
import AppKit
@testable import ClipboardManager

@MainActor
final class PasteInjectorTests: XCTestCase {

    private var pasteboard: NSPasteboard!
    private var blobs: BlobStore!

    override func setUp() async throws {
        try await super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
        blobs = try BlobStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("paste-tests-\(UUID().uuidString)", isDirectory: true))
    }

    override func tearDown() async throws {
        pasteboard?.releaseGlobally()
        try await super.tearDown()
    }

    private func makeTextItem(_ body: String) -> Item {
        Item(
            id: 1, kind: "text", subtype: "plain", contentHash: "h",
            body: body, blobPath: nil, dimensions: nil, byteSize: body.utf8.count,
            sourceApp: nil, sourceBundleId: nil,
            createdAt: Int64(Date().timeIntervalSince1970),
            pinned: false, snippetId: nil, deletedAt: nil
        )
    }

    func testWritesTextToPasteboard() throws {
        let injector = PasteInjector(pasteboard: pasteboard, blobStore: blobs)
        try injector.writeToPasteboard(item: makeTextItem("hello"))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
    }

    func testWritesTextAsPlainStripsRTF() throws {
        let injector = PasteInjector(pasteboard: pasteboard, blobStore: blobs)
        try injector.writeToPasteboard(item: makeTextItem("hi"), asPlainText: true)
        XCTAssertEqual(pasteboard.string(forType: .string), "hi")
        // Plain-text mode does not write rich types.
        XCTAssertFalse(pasteboard.types?.contains(.rtf) ?? false)
    }

    func testWritesImageFromBlob() throws {
        // Write a tiny PNG to the blob store first.
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let png = rep.representation(using: .png, properties: [:])!
        let relPath = try blobs.write(data: png, fileExtension: "png")

        let image = Item(
            id: 2, kind: "image", subtype: nil, contentHash: "h",
            body: relPath, blobPath: relPath, dimensions: "4x4", byteSize: png.count,
            sourceApp: nil, sourceBundleId: nil,
            createdAt: Int64(Date().timeIntervalSince1970),
            pinned: false, snippetId: nil, deletedAt: nil
        )
        let injector = PasteInjector(pasteboard: pasteboard, blobStore: blobs)
        try injector.writeToPasteboard(item: image)
        XCTAssertNotNil(pasteboard.data(forType: .png))
    }

    func testWritesFileURL() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("paste-injector-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let ref = FileReference(path: tmp.path, name: tmp.lastPathComponent,
                                byteSize: 1, modifiedAt: 0)
        let body = try ref.encodedJSON()
        let file = Item(
            id: 3, kind: "file", subtype: nil, contentHash: "h",
            body: body, blobPath: nil, dimensions: nil, byteSize: 1,
            sourceApp: nil, sourceBundleId: nil,
            createdAt: Int64(Date().timeIntervalSince1970),
            pinned: false, snippetId: nil, deletedAt: nil
        )
        let injector = PasteInjector(pasteboard: pasteboard, blobStore: blobs)
        try injector.writeToPasteboard(item: file)

        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(urls?.first?.path, tmp.path)
    }
}
```

- [ ] **Step 2: Verify build fails**

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/Services/PasteInjector.swift
import AppKit
import Foundation
import CoreGraphics

/// Writes a clipboard `Item` back to `NSPasteboard` and then synthesises
/// `⌘V` into the previously-active app.
///
/// The synthesis path requires Accessibility permission. We do not gate the
/// write on permission — even without Accessibility, the pasteboard
/// receives the content, so the user can paste manually.
@MainActor
final class PasteInjector {

    private let pasteboard: NSPasteboard
    private let blobStore: BlobStore

    init(pasteboard: NSPasteboard = .general, blobStore: BlobStore) {
        self.pasteboard = pasteboard
        self.blobStore = blobStore
    }

    // MARK: - Pasteboard writes

    /// Writes the item content to the pasteboard, kind-aware. If
    /// `asPlainText` is true, text items omit any rich-text representation.
    func writeToPasteboard(item: Item, asPlainText: Bool = false) throws {
        pasteboard.clearContents()
        switch item.kind {
        case "text":
            pasteboard.setString(item.body, forType: .string)
        case "image":
            guard let path = item.blobPath else { return }
            let data = try blobStore.read(relativePath: path)
            pasteboard.setData(data, forType: .png)
        case "file":
            let ref = try FileReference.decodingJSON(item.body)
            let url = URL(fileURLWithPath: ref.path)
            pasteboard.writeObjects([url as NSURL])
        default:
            Log.app.error("unknown item kind for paste: \(item.kind, privacy: .public)")
        }
        _ = asPlainText   // currently a no-op; future Phase will branch RTF writes
    }

    // MARK: - Cmd-V synthesis

    /// Posts a `Cmd-V` keyDown + keyUp to the system event tap. If
    /// Accessibility permission is missing, macOS silently drops it.
    func synthesizePasteKeystroke() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        // Key code 9 == 'V'.
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
        Log.app.debug("synthesised ⌘V")
    }

    /// True if the host process has Accessibility permission granted. We
    /// don't prompt here — that's the onboarding's job (Phase 8). But we
    /// can log a hint so the user understands why paste seems to silently
    /// fail the first time.
    var hasAccessibilityPermission: Bool {
        return AXIsProcessTrusted()
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

Expected: 66 tests (62 + 4 new).

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Services/PasteInjector.swift ClipboardManagerTests/PasteInjectorTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "paste: PasteInjector — kind-aware pasteboard writes + ⌘V synthesis"
```

---

## Task 7: Enter-to-paste in DrawerWindow

**Files:**
- Modify: `ClipboardManager/UI/Drawer/DrawerWindow.swift`
- Modify: `ClipboardManager/UI/Drawer/DrawerWindowController.swift`
- Modify: `ClipboardManager/App/AppCoordinator.swift`

The window's keyDown adds an Enter case that:
1. Reads `viewModel.currentItem`.
2. Calls a callback (provided by the controller) that:
   - Writes item to pasteboard via PasteInjector
   - Dismisses the drawer
   - After ~80 ms, posts `⌘V` via PasteInjector.synthesizePasteKeystroke()

The 80 ms delay lets the drawer fully dismiss + give the previously-active app a moment to be the receiver. Without `.nonactivatingPanel` you'd need to actively raise that app, but since our panel doesn't take key focus, the previously-active app remains frontmost across the dismiss.

- [ ] **Step 1: Add a closure to DrawerWindow**

```swift
final class DrawerWindow: NSPanel {
    // ... existing ...

    var onPasteRequested: ((Item, Bool) -> Void)?

    init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore) {
        // ... existing ...
    }
```

Extend keyDown's switch:

```swift
        case 36, 76:   // return, keypad return
            if let item = viewModel.currentItem {
                let asPlain = event.modifierFlags.contains(.shift)
                onPasteRequested?(item, asPlain)
            }
```

- [ ] **Step 2: DrawerWindowController owns the PasteInjector + wires the closure**

```swift
@MainActor
final class DrawerWindowController {
    private let window: DrawerWindow
    private(set) var isVisible: Bool = false
    private var clickOutsideMonitor: Any?

    private let injector: PasteInjector

    init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore, injector: PasteInjector) {
        self.injector = injector
        self.window = DrawerWindow(viewModel: viewModel, blobStore: blobStore, store: store)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDismissRequest),
            name: .drawerDismissRequested, object: nil
        )
        self.window.onPasteRequested = { [weak self] item, asPlain in
            self?.handlePaste(item: item, asPlain: asPlain)
        }
    }

    private func handlePaste(item: Item, asPlain: Bool) {
        do {
            try injector.writeToPasteboard(item: item, asPlainText: asPlain)
        } catch {
            Log.drawer.error("paste write failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        hide()
        // Give the dismissal animation time to start so the previously-active
        // app gets the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.injector.synthesizePasteKeystroke()
        }
    }

    // existing show/hide/toggle/click-outside logic UNCHANGED
}
```

- [ ] **Step 3: AppCoordinator constructs the PasteInjector and wires it**

```swift
@MainActor
final class AppCoordinator {
    // ... add:
    private let pasteInjector: PasteInjector

    init() throws {
        // ... existing store + blobStore + viewModel setup ...
        let injector = PasteInjector(blobStore: blobStore)
        self.pasteInjector = injector

        let drawer = DrawerWindowController(
            viewModel: viewModel, blobStore: blobStore, store: store, injector: injector
        )
        self.drawer = drawer
        // ... rest unchanged ...
    }
    // ...
}
```

- [ ] **Step 4: Build + test**

```bash
make test 2>&1 | tail -10
```

Expected: 66 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerWindow.swift ClipboardManager/UI/Drawer/DrawerWindowController.swift ClipboardManager/App/AppCoordinator.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "paste: Enter pastes focused card into previously-active app"
```

---

## Task 8: Context menu (right-click + ⌘.)

**Files:**
- Modify: `ClipboardManager/UI/Drawer/ClipboardCard.swift`

Add a SwiftUI `.contextMenu` to the card. Actions:
- **Paste** (⏎) — same flow as Enter
- **Paste as Plain Text** (⇧⏎)
- **Copy without Pasting** (⌘C) — write to pasteboard, don't dismiss, don't synthesize
- **Open URL** — only when subtype is url; uses `NSWorkspace.shared.open(URL)`
- **Reveal in Finder** — only when kind is file; uses `NSWorkspace.shared.activateFileViewerSelecting([URL])`
- **Delete** (⌫) — soft-delete via store

Context-menu callbacks live on the card and call closures provided by the view.

- [ ] **Step 1: Add a callback bag to ClipboardCard**

```swift
struct ClipboardCard: View {
    let item: Item
    var isFocused: Bool = false

    // NEW
    var onPaste: ((Item, Bool) -> Void)? = nil
    var onCopy: ((Item) -> Void)? = nil
    var onDelete: ((Item) -> Void)? = nil
    var onOpenURL: ((Item) -> Void)? = nil
    var onRevealInFinder: ((Item) -> Void)? = nil

    // ... existing body ...
```

At the end of the outer `VStack`/body, attach `.contextMenu`:

```swift
        .contextMenu {
            Button("Paste") { onPaste?(item, false) }
                .keyboardShortcut(.return, modifiers: [])
            Button("Paste as Plain Text") { onPaste?(item, true) }
                .keyboardShortcut(.return, modifiers: .shift)
            Button("Copy") { onCopy?(item) }
                .keyboardShortcut("c", modifiers: .command)
            Divider()
            if item.subtype == TextSubtype.url.rawValue {
                Button("Open URL") { onOpenURL?(item) }
            }
            if item.kind == "file" {
                Button("Reveal in Finder") { onRevealInFinder?(item) }
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete?(item) }
        }
```

- [ ] **Step 2: DrawerView wires the closures**

Edit DrawerView. In the `ClipboardCard` construction:

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
```

Add these closures as properties of DrawerView (so the controller can inject them):

```swift
struct DrawerView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let blobStore: BlobStore?
    var onPaste: ((Item, Bool) -> Void)? = nil
    var onCopy: ((Item) -> Void)? = nil
    var onDelete: ((Item) -> Void)? = nil
    var onOpenURL: ((Item) -> Void)? = nil
    var onRevealInFinder: ((Item) -> Void)? = nil
    // ... rest ...
```

- [ ] **Step 3: DrawerWindow forwards the closures**

```swift
init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore,
     onPaste: @escaping (Item, Bool) -> Void,
     onCopy: @escaping (Item) -> Void,
     onDelete: @escaping (Item) -> Void,
     onOpenURL: @escaping (Item) -> Void,
     onRevealInFinder: @escaping (Item) -> Void) {
    // existing super.init setup ...

    let host = NSHostingView(rootView: DrawerView(
        viewModel: viewModel, blobStore: blobStore,
        onPaste: onPaste, onCopy: onCopy, onDelete: onDelete,
        onOpenURL: onOpenURL, onRevealInFinder: onRevealInFinder
    ))
    // ... rest
}
```

You can drop the `onPasteRequested` closure pattern from Task 7 and consolidate into the new bag.

- [ ] **Step 4: DrawerWindowController builds the closures**

Replace the controller's init with:

```swift
init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore, injector: PasteInjector) {
    self.injector = injector
    // Build all the closures up front using local capture (avoids needing self before super.init).
    let pasteHandler: (Item, Bool) -> Void = { item, asPlain in
        Task { @MainActor in
            // Window controller has to dispatch; use a notification or weak self pattern.
        }
    }
    // ...
}
```

Practical approach: instead of building closures in init (chicken-and-egg with `self`), set the window's closures AFTER calling DrawerWindow's init. The cleanest variant:

```swift
@MainActor
final class DrawerWindowController {
    private let window: DrawerWindow
    private(set) var isVisible: Bool = false
    private var clickOutsideMonitor: Any?
    private let injector: PasteInjector
    private let store: ClipboardStore

    init(viewModel: ClipboardViewModel, blobStore: BlobStore?, store: ClipboardStore, injector: PasteInjector) {
        self.store = store
        self.injector = injector

        // Create the window with the bag of closures — bind to a method after self is initialised.
        var pasteHandler: ((Item, Bool) -> Void)!
        var copyHandler: ((Item) -> Void)!
        var deleteHandler: ((Item) -> Void)!
        var openURLHandler: ((Item) -> Void)!
        var revealHandler: ((Item) -> Void)!

        self.window = DrawerWindow(
            viewModel: viewModel, blobStore: blobStore, store: store,
            onPaste: { item, asPlain in pasteHandler(item, asPlain) },
            onCopy: { item in copyHandler(item) },
            onDelete: { item in deleteHandler(item) },
            onOpenURL: { item in openURLHandler(item) },
            onRevealInFinder: { item in revealHandler(item) }
        )

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDismissRequest),
            name: .drawerDismissRequested, object: nil
        )

        pasteHandler = { [weak self] item, asPlain in self?.handlePaste(item: item, asPlain: asPlain) }
        copyHandler = { [weak self] item in self?.handleCopy(item: item) }
        deleteHandler = { [weak self] item in self?.handleDelete(item: item) }
        openURLHandler = { [weak self] item in self?.handleOpenURL(item: item) }
        revealHandler = { [weak self] item in self?.handleReveal(item: item) }
    }

    private func handlePaste(item: Item, asPlain: Bool) {
        do { try injector.writeToPasteboard(item: item, asPlainText: asPlain) }
        catch { Log.drawer.error("paste write failed: \(error.localizedDescription, privacy: .public)"); return }
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.injector.synthesizePasteKeystroke()
        }
    }

    private func handleCopy(item: Item) {
        do { try injector.writeToPasteboard(item: item) }
        catch { Log.drawer.error("copy write failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func handleDelete(item: Item) {
        guard let id = item.id else { return }
        do { try store.softDelete(itemId: id) }
        catch { Log.drawer.error("delete failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func handleOpenURL(item: Item) {
        guard item.subtype == TextSubtype.url.rawValue,
              let url = URL(string: item.body) else { return }
        NSWorkspace.shared.open(url)
        hide()
    }

    private func handleReveal(item: Item) {
        guard item.kind == "file",
              let ref = try? FileReference.decodingJSON(item.body) else { return }
        let url = URL(fileURLWithPath: ref.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        hide()
    }

    // ... existing show/hide/toggle/dismiss-request/click-outside unchanged ...
}
```

- [ ] **Step 5: Build + test**

```bash
make test 2>&1 | tail -10
```

Expected: 66 tests still pass.

- [ ] **Step 6: Commit**

```bash
git add ClipboardManager/UI/Drawer/ClipboardCard.swift ClipboardManager/UI/Drawer/DrawerView.swift ClipboardManager/UI/Drawer/DrawerWindow.swift ClipboardManager/UI/Drawer/DrawerWindowController.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "ui: context menu (paste/copy/open URL/reveal in Finder/delete)"
```

---

## Task 9: Hover preview popover

**Files:**
- Create: `ClipboardManager/UI/Drawer/HoverPreview.swift`
- Modify: `ClipboardManager/UI/Drawer/ClipboardCard.swift` (emit hover events with frame)
- Modify: `ClipboardManager/UI/Drawer/DrawerView.swift` (debounced hover state)
- Modify: `ClipboardManager/UI/Drawer/DrawerWindow.swift` + Controller (show/hide preview window)

This is the most visible bit of polish. We use a second NSPanel ("HoverPreviewPanel") that floats above the drawer. SwiftUI cards report their on-screen frame via `GeometryReader`/`NamedCoordinateSpace` after 400 ms of hover.

Given the complexity, here we ship a **simpler v1**: a SwiftUI overlay positioned at the focused card's frame, rendered inside the drawer's own window. It's less accurate (clipped by drawer) but ships now.

If you need a real out-of-window popover later, that's a Phase 4.5 enhancement.

- [ ] **Step 1: Add the hover preview view**

```swift
// ClipboardManager/UI/Drawer/HoverPreview.swift
import SwiftUI
import AppKit

struct HoverPreviewContent: View {
    let item: Item
    @Environment(\.blobStore) private var blobStore
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        Group {
            switch item.kind {
            case "image":
                if let path = item.blobPath,
                   let blobStore,
                   let nsImage = NSImage(contentsOf: blobStore.absoluteURL(forRelativePath: path)) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 380, maxHeight: 240)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 380, height: 240)
                }
            case "file":
                fileBlock
            default:
                ScrollView {
                    Text(item.body)
                        .font(item.subtype == TextSubtype.code.rawValue || item.subtype == TextSubtype.json.rawValue
                              ? .system(size: 12, design: .monospaced)
                              : .system(size: 13))
                        .textSelection(.enabled)
                        .padding(14)
                }
                .frame(width: 340, height: 240)
            }
        }
        .background(VisualEffectBackground(material: DesignMaterials.popover(dark: dark)))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(dark ? 0.4 : 0.15), radius: 16, y: 8)
    }

    private var fileBlock: some View {
        let ref = try? FileReference.decodingJSON(item.body)
        return VStack(alignment: .leading, spacing: 6) {
            Text(ref?.name ?? "Unknown")
                .font(.system(size: 14, weight: .semibold))
            if let path = ref?.path {
                Text(path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let size = ref?.formattedSize {
                Text(size)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
```

- [ ] **Step 2: Wire hover state into DrawerView**

Add to DrawerView:

```swift
    @State private var hoveredID: Int64? = nil
    @State private var hoverTimer: DispatchWorkItem? = nil
    @State private var debouncedHoveredItem: Item? = nil
```

When constructing each card:

```swift
ClipboardCard(item: item, isFocused: idx == viewModel.focusedIndex, /* callbacks */)
    .onHover { hovering in
        hoverTimer?.cancel()
        if hovering {
            let id = item.id
            let work = DispatchWorkItem { [weak viewModel = self.viewModel] in
                _ = viewModel
                debouncedHoveredItem = item
                hoveredID = id
            }
            hoverTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        } else if hoveredID == item.id {
            debouncedHoveredItem = nil
            hoveredID = nil
        }
    }
```

Below the `cardStrip` inside the body's ZStack, add a positioned overlay:

```swift
            if let hovered = debouncedHoveredItem {
                HoverPreviewContent(item: hovered)
                    .padding(.top, 40)   // sit just below the top bar
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .animation(.easeOut(duration: 0.18), value: debouncedHoveredItem?.id)
            }
```

This places the preview inside the drawer near the top — not a separate window. It's the minimum-effort path that gives meaningful preview UX.

- [ ] **Step 3: Build + test**

```bash
make test 2>&1 | tail -10
```

Expected: 66 tests pass.

- [ ] **Step 4: Commit**

```bash
git add ClipboardManager/UI/Drawer/HoverPreview.swift ClipboardManager/UI/Drawer/DrawerView.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "ui: hover preview (400ms debounce) for focused card"
```

---

## Task 10: Smoke verify + tag v0.4.0

- [ ] **Step 1: Rebuild + relaunch**

```bash
cd /Users/gal.lev/Clipboard
killall ClipboardManager 2>/dev/null; sleep 1
make build 2>&1 | tail -3
APP_DIR=$(xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/ {print $3; exit}')
open -g "$APP_DIR/ClipboardManager.app"
```

- [ ] **Step 2: User verification**

Ask the user to confirm in the running app:
1. Press `⌘⇧V`, see tabs and search field in the top bar, count + hint in the bottom bar.
2. Use `←` / `→` to move focus — focused card has a blue accent border.
3. Use `⌘1`, `⌘2`, …, `⌘9` to jump.
4. Click tabs to filter (All / Text / Images / Files / Pinned).
5. Click the search icon (or use the search field directly) — typing filters cards live.
6. Right-click a card — see context menu with Paste / Paste as Plain Text / Copy / Open URL / Reveal in Finder / Delete.
7. Hover over a card for ~½ second — preview popover appears with full content.
8. Click on a text item, press Enter — drawer dismisses and the text pastes into the previously-active app.
9. Press `⌫` on a focused card — it disappears from the drawer.

If Accessibility permission hasn't been granted, the paste-injection step (8) won't simulate `⌘V` but the pasteboard still has the item. macOS will surface the prompt the first time we try. Grant + retry.

- [ ] **Step 3: Tag**

```bash
git tag -a v0.4.0-phase4 -m "Phase 4 complete: tabs, search, keyboard nav, paste injection, context menu, hover preview"
git log --oneline v0.3.1..v0.4.0-phase4
```

## Phase 4 — Done criteria

- [ ] `make test` passes (66 tests).
- [ ] Tabs filter the strip correctly (Pinned is empty).
- [ ] Search filters live with no UI lag.
- [ ] Arrow keys, ⌘1–9, and ⌫ all work on the focused card.
- [ ] Enter on a text card pastes the text into the previously-active app within ~150 ms.
- [ ] Right-click reveals the context menu and Open URL / Reveal in Finder dismiss the drawer afterwards.
- [ ] Hovering for ~400 ms reveals a preview.
- [ ] `v0.4.0-phase4` tag exists.

## What's next (Phase 5 preview)

Snippets: a `snippets` table, "Pin to Snippets" action wired up, the Pinned tab becomes the live snippet library, snippet editor in Preferences (Phase 7 too). Plus the keyword-expansion CGEventTap (Phase 6 in the original phasing, but combined here as it's a natural extension of the snippet feature).
