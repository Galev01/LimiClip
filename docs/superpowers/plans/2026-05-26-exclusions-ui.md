# App Exclusions UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Privacy pane to Preferences where users can view and manage which apps are excluded from clipboard history.

**Architecture:** ExclusionsViewModel wraps ClipboardStore and is injected from AppCoordinator into PreferencesWindowController and down to PrivacyPane. NSOpenPanel extracts bundle IDs from .app packages.

**Tech Stack:** Swift 6.0, SwiftUI Form, AppKit NSOpenPanel, GRDB (via ClipboardStore)

---

## File Structure

```
ClipboardManager/
├── UI/
│   └── Preferences/
│       ├── PreferencesView.swift              (MODIFIED — add .privacy case to enum + switch)
│       ├── PreferencesWindowController.swift  (MODIFIED — accept ExclusionsViewModel param)
│       └── PrivacyPane.swift                  (NEW)
├── ViewModels/
│   └── ExclusionsViewModel.swift              (NEW)
└── App/
    └── AppCoordinator.swift                   (MODIFIED — create ExclusionsViewModel, pass to controller)

ClipboardManagerTests/
└── ExclusionsViewModelTests.swift             (NEW)
```

---

## Pre-flight

```bash
cd /Users/gal.lev/Clipboard
make test 2>&1 | tail -5
```

Expected: all tests pass. The current passing count can be confirmed from the last line of output (look for `** TEST SUCCEEDED **`).

---

## Task 1: ExclusionsViewModel (TDD)

`ExclusionsViewModel` is a `@MainActor ObservableObject` that wraps `ClipboardStore` exclusion operations and re-publishes them as a sorted `[Exclusion]` list. It reloads on `clipboardStoreDidChange` notifications so it stays in sync with any other code path that mutates the exclusions table.

**Files:**
- Create: `ClipboardManager/ViewModels/ExclusionsViewModel.swift`
- Create: `ClipboardManagerTests/ExclusionsViewModelTests.swift`

### Step 1.1 — Write the failing tests

Create `/Users/gal.lev/Clipboard/ClipboardManagerTests/ExclusionsViewModelTests.swift`:

```swift
// ClipboardManagerTests/ExclusionsViewModelTests.swift
import XCTest
@testable import ClipboardManager

@MainActor
final class ExclusionsViewModelTests: XCTestCase {

    private func makeStore() throws -> ClipboardStore {
        try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    }

    // MARK: - init

    func testInitLoadsExistingExclusions() throws {
        let store = try makeStore()
        try store.addExclusion(bundleId: "com.example.app", name: "Example App")
        let vm = ExclusionsViewModel(store: store)
        XCTAssertEqual(vm.exclusions.count, 1)
        XCTAssertEqual(vm.exclusions[0].bundleId, "com.example.app")
        XCTAssertEqual(vm.exclusions[0].name, "Example App")
    }

    func testInitWithEmptyStoreProducesEmptyList() throws {
        let store = try makeStore()
        let vm = ExclusionsViewModel(store: store)
        XCTAssertTrue(vm.exclusions.isEmpty)
    }

    // MARK: - add

    func testAddExclusionAppearsInList() throws {
        let store = try makeStore()
        let vm = ExclusionsViewModel(store: store)
        XCTAssertTrue(vm.exclusions.isEmpty)
        vm.add(bundleId: "com.test.browser", name: "Test Browser")
        XCTAssertEqual(vm.exclusions.count, 1)
        XCTAssertEqual(vm.exclusions[0].bundleId, "com.test.browser")
    }

    func testAddDuplicateBundleIdIsIdempotent() throws {
        let store = try makeStore()
        let vm = ExclusionsViewModel(store: store)
        vm.add(bundleId: "com.dupe", name: "Dupe App")
        vm.add(bundleId: "com.dupe", name: "Dupe App")
        XCTAssertEqual(vm.exclusions.count, 1)
    }

    // MARK: - remove

    func testRemoveExclusionDisappearsFromList() throws {
        let store = try makeStore()
        try store.addExclusion(bundleId: "com.to.remove", name: "To Remove")
        let vm = ExclusionsViewModel(store: store)
        XCTAssertEqual(vm.exclusions.count, 1)
        vm.remove(bundleId: "com.to.remove")
        XCTAssertTrue(vm.exclusions.isEmpty)
    }

    func testRemoveNonExistentBundleIdIsNoOp() throws {
        let store = try makeStore()
        try store.addExclusion(bundleId: "com.kept", name: "Kept")
        let vm = ExclusionsViewModel(store: store)
        vm.remove(bundleId: "com.does.not.exist")
        XCTAssertEqual(vm.exclusions.count, 1)
    }

    // MARK: - sorted order

    func testExclusionsAreSortedByName() throws {
        let store = try makeStore()
        try store.addExclusion(bundleId: "com.z", name: "Zebra")
        try store.addExclusion(bundleId: "com.a", name: "Apple")
        try store.addExclusion(bundleId: "com.m", name: "Mango")
        let vm = ExclusionsViewModel(store: store)
        XCTAssertEqual(vm.exclusions.map(\.name), ["Apple", "Mango", "Zebra"])
    }

    // MARK: - notification reload

    func testStoreDidChangeNotificationReloadsExclusions() throws {
        let store = try makeStore()
        let vm = ExclusionsViewModel(store: store)
        XCTAssertTrue(vm.exclusions.isEmpty)

        // Add via store directly (bypasses vm), then fire the notification manually.
        try store.addExclusion(bundleId: "com.notified", name: "Notified App")
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)

        XCTAssertEqual(vm.exclusions.count, 1)
        XCTAssertEqual(vm.exclusions[0].name, "Notified App")
    }
}
```

### Step 1.2 — Verify the build fails

```bash
cd /Users/gal.lev/Clipboard
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager \
    -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD FAILED"
```

Expected: `error: cannot find type 'ExclusionsViewModel'` and `BUILD FAILED`.

### Step 1.3 — Implement ExclusionsViewModel

First check whether a `ViewModels` directory already exists:

```bash
ls /Users/gal.lev/Clipboard/ClipboardManager/ViewModels/ 2>/dev/null || echo "DOES NOT EXIST"
```

If it does not exist, create it:

```bash
mkdir -p /Users/gal.lev/Clipboard/ClipboardManager/ViewModels
```

Create `/Users/gal.lev/Clipboard/ClipboardManager/ViewModels/ExclusionsViewModel.swift`:

```swift
// ClipboardManager/ViewModels/ExclusionsViewModel.swift
import Foundation
import Combine

@MainActor
final class ExclusionsViewModel: ObservableObject {

    @Published private(set) var exclusions: [Exclusion] = []

    private let store: ClipboardStore
    private var notificationToken: NSObjectProtocol?

    init(store: ClipboardStore) {
        self.store = store
        reload()
        notificationToken = NotificationCenter.default.addObserver(
            forName: .clipboardStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Already on main queue; hop to MainActor for @Published mutation.
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    deinit {
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Public API

    func add(bundleId: String, name: String) {
        do {
            try store.addExclusion(bundleId: bundleId, name: name)
            reload()
        } catch {
            Log.app.error("ExclusionsViewModel.add failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func remove(bundleId: String) {
        do {
            try store.removeExclusion(bundleId: bundleId)
            reload()
        } catch {
            Log.app.error("ExclusionsViewModel.remove failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func reload() {
        do {
            exclusions = try store.allExclusions()
        } catch {
            Log.app.error("ExclusionsViewModel.reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

**Design notes:**
- `reload()` is called eagerly in `init` (synchronous, on MainActor — safe because `ClipboardStore.allExclusions()` is a read-only GRDB call that returns immediately).
- `NotificationCenter` token is stored so it is properly torn down in `deinit`.
- `add` and `remove` call `reload()` directly after the store write rather than waiting for the notification, so the UI updates synchronously within the same runloop turn.
- The notification observer additionally calls `reload()` to handle mutations from other code paths (e.g. `PasteboardMonitor` calling `store.addExclusion` in the future).

### Step 1.4 — Run tests

```bash
cd /Users/gal.lev/Clipboard
make test 2>&1 | tail -10
```

Expected: all previously passing tests still pass, plus the 8 new `ExclusionsViewModelTests` pass.

### Step 1.5 — Commit

```bash
cd /Users/gal.lev/Clipboard
git add ClipboardManager/ViewModels/ExclusionsViewModel.swift \
        ClipboardManagerTests/ExclusionsViewModelTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" \
    commit -m "viewmodel: ExclusionsViewModel wraps store exclusion CRUD"
```

---

## Task 2: PrivacyPane view

A SwiftUI `Form` with a sectioned list of excluded apps. Each row shows the app name with a destructive delete button. An "Add App..." button opens `NSOpenPanel` restricted to `.app` bundles; on selection the panel reads `Info.plist` to extract `CFBundleIdentifier` and `CFBundleName`.

**Files:**
- Create: `ClipboardManager/UI/Preferences/PrivacyPane.swift`

No unit tests for this task — pure UI. Manual smoke-testing covered in Task 4.

### Step 2.1 — Create PrivacyPane

Create `/Users/gal.lev/Clipboard/ClipboardManager/UI/Preferences/PrivacyPane.swift`:

```swift
// ClipboardManager/UI/Preferences/PrivacyPane.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PrivacyPane: View {
    @ObservedObject var viewModel: ExclusionsViewModel

    var body: some View {
        Form {
            Section {
                if viewModel.exclusions.isEmpty {
                    Text("No apps excluded. Clipboard history records copies from all apps.")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else {
                    ForEach(viewModel.exclusions, id: \.bundleId) { exclusion in
                        HStack {
                            Label(exclusion.name, systemImage: "app.badge.checkmark")
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.remove(bundleId: exclusion.bundleId)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove \(exclusion.name) from exclusions")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Excluded Apps")
                    Spacer()
                    Button("Add App…") {
                        addAppFromPanel()
                    }
                    .font(.system(size: 12))
                }
            } footer: {
                Text("Clipboard history will not record copies made in excluded apps.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - NSOpenPanel

    private func addAppFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.prompt = "Exclude"
        panel.message = "Select an app to exclude from clipboard history:"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        // Restrict to /Applications and ~/Applications for a tidy picker.
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let (bundleId, name) = extractBundleInfo(from: url) else {
            Log.app.warning("PrivacyPane: could not read Info.plist from \(url.path, privacy: .public)")
            return
        }

        viewModel.add(bundleId: bundleId, name: name)
    }

    /// Reads `Contents/Info.plist` inside the chosen `.app` bundle and returns
    /// `(CFBundleIdentifier, CFBundleName)`, or `nil` on any failure.
    private func extractBundleInfo(from appURL: URL) -> (bundleId: String, name: String)? {
        let plistURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")

        guard
            let dict = NSDictionary(contentsOf: plistURL),
            let bundleId = dict["CFBundleIdentifier"] as? String,
            !bundleId.isEmpty
        else { return nil }

        // Prefer CFBundleDisplayName (localised), fall back to CFBundleName, then
        // the file-system name (strip the ".app" extension).
        let name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent

        return (bundleId, name)
    }
}

#Preview {
    // Provide a throw-away in-memory store for the canvas.
    let store = try! ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    try! store.addExclusion(bundleId: "com.agilebits.onepassword7", name: "1Password 7")
    try! store.addExclusion(bundleId: "com.bitwarden.desktop", name: "Bitwarden")
    let vm = ExclusionsViewModel(store: store)
    return PrivacyPane(viewModel: vm)
        .frame(width: 400, height: 400)
}
```

**Design notes:**
- `canChooseFiles = false` / `canChooseDirectories = true` is the correct pairing for `.app` bundles on macOS — `.app` packages are directories on disk. `allowedContentTypes: [.applicationBundle]` additionally filters to UTType `com.apple.application-bundle`.
- `CFBundleDisplayName` is checked before `CFBundleName` to get the user-visible localised name (e.g. "App Store" not "MAS").
- The delete button uses `role: .destructive` so VoiceOver announces it correctly; the `.plain` button style prevents the Form from wrapping it in a bordered control.
- The "Add App…" button lives in the section header alongside the title, matching the macOS HIG pattern for list-management controls.

### Step 2.2 — Build check

```bash
cd /Users/gal.lev/Clipboard
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager \
    -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. The `.privacy` case does not exist yet — that is fine, `PrivacyPane` is defined but not yet wired into `PreferencesView`.

### Step 2.3 — Commit

```bash
cd /Users/gal.lev/Clipboard
git add ClipboardManager/UI/Preferences/PrivacyPane.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" \
    commit -m "ui: PrivacyPane with exclusions list and NSOpenPanel app picker"
```

---

## Task 3: Add .privacy to PreferencesPane + PreferencesView

Add the new sidebar entry and route it to `PrivacyPane`. `PreferencesView` gains an `exclusionsVM` init parameter so the view model flows in from the outside.

**Files:**
- Modify: `ClipboardManager/UI/Preferences/PreferencesView.swift`

### Step 3.1 — Read the current file

Read `/Users/gal.lev/Clipboard/ClipboardManager/UI/Preferences/PreferencesView.swift` to confirm its current state before editing.

### Step 3.2 — Apply the changes

The full replacement for `PreferencesView.swift`:

```swift
// ClipboardManager/UI/Preferences/PreferencesView.swift
import SwiftUI

enum PreferencesPane: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case privacy

    var id: String { rawValue }
    var label: String {
        switch self {
        case .general:   return "General"
        case .shortcuts: return "Shortcuts"
        case .privacy:   return "Privacy"
        }
    }
    var symbol: String {
        switch self {
        case .general:   return "gearshape"
        case .shortcuts: return "keyboard"
        case .privacy:   return "hand.raised"
        }
    }
}

struct PreferencesView: View {
    let exclusionsVM: ExclusionsViewModel

    @State private var selected: PreferencesPane = .general

    init(exclusionsVM: ExclusionsViewModel) {
        self.exclusionsVM = exclusionsVM
    }

    var body: some View {
        NavigationSplitView {
            List(PreferencesPane.allCases, selection: $selected) { pane in
                Label(pane.label, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selected {
                case .general:   GeneralPane()
                case .shortcuts: ShortcutsPane()
                case .privacy:   PrivacyPane(viewModel: exclusionsVM)
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(selected.label)
        }
    }
}

#Preview {
    let store = try! ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    let vm = ExclusionsViewModel(store: store)
    return PreferencesView(exclusionsVM: vm)
        .frame(width: 600, height: 400)
}
```

**Key change:** `PreferencesView` now requires `exclusionsVM: ExclusionsViewModel` — the zero-argument init is gone. This will break `PreferencesWindowController.show()` at the call site; that is intentional and fixed in Task 4.

### Step 3.3 — Build check (expected failure at call site)

```bash
cd /Users/gal.lev/Clipboard
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager \
    -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD FAILED|BUILD SUCCEEDED"
```

Expected outcome: the build **fails** with an error along the lines of `missing argument for parameter 'exclusionsVM' in call` inside `PreferencesWindowController.swift`. That is the expected state — Task 4 resolves it.

### Step 3.4 — Commit

```bash
cd /Users/gal.lev/Clipboard
git add ClipboardManager/UI/Preferences/PreferencesView.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" \
    commit -m "prefs: add Privacy pane to PreferencesPane enum + PreferencesView"
```

---

## Task 4: Thread ExclusionsViewModel through PreferencesWindowController + AppCoordinator

Wire the view model from `AppCoordinator` (where the store lives) down to `PreferencesWindowController` and into `PreferencesView`. This task makes the project build and the full test suite pass again.

**Files:**
- Modify: `ClipboardManager/UI/Preferences/PreferencesWindowController.swift`
- Modify: `ClipboardManager/App/AppCoordinator.swift`

### Step 4.1 — Read current files

Read both files before editing:
- `/Users/gal.lev/Clipboard/ClipboardManager/UI/Preferences/PreferencesWindowController.swift`
- `/Users/gal.lev/Clipboard/ClipboardManager/App/AppCoordinator.swift`

### Step 4.2 — Update PreferencesWindowController

Full replacement for `/Users/gal.lev/Clipboard/ClipboardManager/UI/Preferences/PreferencesWindowController.swift`:

```swift
// ClipboardManager/UI/Preferences/PreferencesWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController {

    private let exclusionsVM: ExclusionsViewModel
    private var window: NSWindow?

    init(exclusionsVM: ExclusionsViewModel) {
        self.exclusionsVM = exclusionsVM
    }

    /// Brings the preferences window to the front, creating it if necessary.
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(
            rootView: PreferencesView(exclusionsVM: exclusionsVM)
        )
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Clipboard Manager — Preferences"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 600, height: 400))
        newWindow.minSize = NSSize(width: 560, height: 380)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.identifier = NSUserInterfaceItemIdentifier("preferences")

        // Make the preferences window force the app to act regular while open,
        // so it can take key focus and respond to ⌘W / ⌘Q like a normal window.
        NSApp.setActivationPolicy(.regular)
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow

        // When the window closes, revert to accessory so we go back to being
        // a pure menu-bar agent.
        let center = NotificationCenter.default
        var token: NSObjectProtocol?
        token = center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            if let token { center.removeObserver(token) }
            NSApp.setActivationPolicy(.accessory)
            self?.window = nil
        }
    }
}
```

### Step 4.3 — Update AppCoordinator

Read `/Users/gal.lev/Clipboard/ClipboardManager/App/AppCoordinator.swift` (already read in pre-flight — verify nothing has changed). Then apply these targeted edits:

**Change 1:** Replace the stored property declaration for `preferencesWindow`:

Old:
```swift
    private let preferencesWindow = PreferencesWindowController()
```

New:
```swift
    private let exclusionsVM: ExclusionsViewModel
    private let preferencesWindow: PreferencesWindowController
```

**Change 2:** Inside `init()`, after `self.store = store`, add the view model and controller creation. Insert immediately after:

```swift
        self.store = store
```

Add:

```swift
        let exclusionsVM = ExclusionsViewModel(store: store)
        self.exclusionsVM = exclusionsVM
        self.preferencesWindow = PreferencesWindowController(exclusionsVM: exclusionsVM)
```

**Change 3:** Remove the old implicit `preferencesWindow` capture. The existing line:

```swift
        let prefs = self.preferencesWindow
```

can remain unchanged — it captures the now-explicitly-initialised controller.

The full resulting `init()` body in `AppCoordinator` should look like:

```swift
    init() throws {
        let store = try ClipboardStore()
        try store.seedDefaultExclusionsIfNeeded()
        self.store = store

        let exclusionsVM = ExclusionsViewModel(store: store)
        self.exclusionsVM = exclusionsVM
        self.preferencesWindow = PreferencesWindowController(exclusionsVM: exclusionsVM)

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
```

### Step 4.4 — Build

```bash
cd /Users/gal.lev/Clipboard
make build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

If the build fails with a Swift 6 concurrency error on `ExclusionsViewModel` being non-`Sendable` when captured across actor boundaries: `ExclusionsViewModel` is `@MainActor`-isolated, which satisfies `Sendable` under Swift 6 strict concurrency. If the compiler still complains, annotate the stored property:

```swift
    @MainActor private let exclusionsVM: ExclusionsViewModel
```

### Step 4.5 — Run full test suite

```bash
cd /Users/gal.lev/Clipboard
make test 2>&1 | tail -10
```

Expected: all tests pass (previously passing count + 8 new `ExclusionsViewModelTests`). Look for `** TEST SUCCEEDED **`.

### Step 4.6 — Commit

```bash
cd /Users/gal.lev/Clipboard
git add ClipboardManager/UI/Preferences/PreferencesWindowController.swift \
        ClipboardManager/App/AppCoordinator.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" \
    commit -m "wire: thread ExclusionsViewModel from AppCoordinator into PrivacyPane"
```

---

## Manual Smoke-Test Checklist

Run after Task 4 completes. Ask Gal to verify:

- [ ] Open Preferences (⌘, from menu bar dropdown). Three sidebar items appear: General, Shortcuts, Privacy.
- [ ] Click **Privacy**. The pane loads with a list of seeded exclusions (1Password 7, 1Password, Bitwarden, Keychain Access, LastPass, Dashlane).
- [ ] Click the red **minus** button next to one entry (e.g. Bitwarden). It disappears from the list immediately.
- [ ] Click **Add App…**. An NSOpenPanel opens at `/Applications`. Navigate to an app (e.g. Safari.app). Click **Exclude**. The app appears in the list with its display name and bundle ID is stored.
- [ ] Close and reopen Preferences → Privacy. The list persists (stored in SQLite).
- [ ] Copy something in the newly excluded app, then open the Clipboard drawer. Confirm the copy does not appear.
- [ ] The empty-state message ("No apps excluded…") appears when all entries are removed.

---

## Done Criteria

- [ ] `make test` passes (all previously passing tests + 8 new `ExclusionsViewModelTests`).
- [ ] `make build` succeeds with zero warnings on the new files.
- [ ] Privacy pane appears as the third sidebar item in Preferences.
- [ ] Add App... panel opens, correctly extracts bundle ID + display name, and saves to DB.
- [ ] Delete button removes exclusion from DB and UI immediately.
- [ ] `ExclusionsViewModel` reacts to external `clipboardStoreDidChange` notifications.
- [ ] Empty-state message shown when list is empty.
- [ ] No regressions in existing clipboard recording, retention, or settings behaviour.

## What's Next

- Snippets pane: pin items, keyword expansion, snippet library (a new `PreferencesPane.snippets` case following the same pattern).
- Show app icon (retrieved via `NSWorkspace.shared.icon(forFile:)`) next to the app name in each Privacy row for a more polished look.
- Consider exposing a "Re-add defaults" button to restore the seeded password manager exclusions if a user accidentally removes them all.
