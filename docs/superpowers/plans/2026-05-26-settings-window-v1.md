# Clipboard Manager — Settings Window v1

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A small, native macOS preferences window with two panes: **General** (launch-at-login, appearance, history limits, hover-preview toggle) and **Shortcuts** (rebindable `⌘⇧V` and `⌘⇧A`). Reachable via a menu-bar dropdown.

**Scope notes:**
- Settings persistence: `@AppStorage` (UserDefaults) for booleans/enums. `KeyboardShortcuts` already persists its own state, so the Shortcuts pane is mostly a thin wrapper around their `Recorder` view.
- Launch at Login uses `ServiceManagement.SMAppService` (macOS 13+ API, no helper bundle).
- Appearance applies app-wide via `NSApp.appearance`. System = nil (track macOS).
- Retention values feed `RetentionJob` via a getter — no need to restart the job on every change; it re-reads on each hourly tick.
- Hover preview can be disabled — DrawerView reads the setting on each show.

**Tech stack additions:** None — `KeyboardShortcuts.Recorder` and `SMAppService` are already linked. `@AppStorage` is SwiftUI built-in.

**Verification target:**
- Left-clicking the menu bar icon shows a dropdown (Open Clipboard / Preferences… / Quit), not the drawer.
- The `⌘⇧V` global hotkey still toggles the drawer.
- Preferences… opens a 560×400 window with two sidebar items (General, Shortcuts).
- General toggles persist across launches.
- Recording a new hotkey in Shortcuts immediately updates the global binding.

---

## File Structure

```
ClipboardManager/
├── Settings.swift                                 (NEW — typed @AppStorage keys + LaunchAtLogin helper)
├── UI/
│   ├── MenuBar/
│   │   └── MenuBarController.swift                (MODIFIED — NSMenu with three items)
│   └── Preferences/                               (NEW DIRECTORY)
│       ├── PreferencesWindowController.swift      (NEW — owns NSWindow lifecycle)
│       ├── PreferencesView.swift                  (NEW — SwiftUI root, NavigationSplitView)
│       ├── GeneralPane.swift                      (NEW)
│       └── ShortcutsPane.swift                    (NEW)
├── App/
│   └── AppCoordinator.swift                       (MODIFIED — owns PreferencesWindowController, applies appearance, wires menu bar)
└── Services/
    └── RetentionJob.swift                          (MODIFIED — reads count + days from Settings instead of init params)

ClipboardManagerTests/
└── SettingsTests.swift                            (NEW — round-trip + default values)
```

---

## Pre-flight

```bash
cd /Users/gal.lev/Clipboard
git log --oneline -1   # should be 92fec8e or a later signing-related commit
make test 2>&1 | tail -3
```

Expected: 66 tests pass.

---

## Task 1: Settings module (TDD)

A single namespace exposes typed accessors for every persisted setting. UserDefaults keys are constants — never typo-stringly elsewhere.

**Files:**
- Create: `ClipboardManager/Settings.swift`
- Create: `ClipboardManagerTests/SettingsTests.swift`

- [ ] **Step 1: Failing tests**

`/Users/gal.lev/Clipboard/ClipboardManagerTests/SettingsTests.swift`:

```swift
import XCTest
@testable import ClipboardManager

final class SettingsTests: XCTestCase {

    /// We exercise a private UserDefaults instance so tests don't pollute the
    /// real app's settings.
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "settings-tests-\(UUID().uuidString)")
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "")
    }

    func testAppearanceDefaultIsSystem() {
        XCTAssertEqual(Settings(defaults: defaults).appearance, .system)
    }

    func testAppearanceRoundtrips() {
        var s = Settings(defaults: defaults)
        s.appearance = .dark
        XCTAssertEqual(Settings(defaults: defaults).appearance, .dark)
        s.appearance = .light
        XCTAssertEqual(Settings(defaults: defaults).appearance, .light)
    }

    func testHistoryLimitDefaultIs5000() {
        XCTAssertEqual(Settings(defaults: defaults).historyLimit, 5000)
    }

    func testHistoryLimitRoundtrips() {
        var s = Settings(defaults: defaults)
        s.historyLimit = 1000
        XCTAssertEqual(Settings(defaults: defaults).historyLimit, 1000)
    }

    func testRetentionDaysDefaultIs90() {
        XCTAssertEqual(Settings(defaults: defaults).retentionDays, 90)
    }

    func testShowHoverPreviewDefaultIsTrue() {
        XCTAssertTrue(Settings(defaults: defaults).showHoverPreview)
    }

    func testShowHoverPreviewRoundtrips() {
        var s = Settings(defaults: defaults)
        s.showHoverPreview = false
        XCTAssertFalse(Settings(defaults: defaults).showHoverPreview)
    }

    func testAppearanceEnumStableRawValues() {
        // External code (UI bindings) may rely on these — keep them stable.
        XCTAssertEqual(AppAppearance.system.rawValue, "system")
        XCTAssertEqual(AppAppearance.light.rawValue, "light")
        XCTAssertEqual(AppAppearance.dark.rawValue, "dark")
    }
}
```

- [ ] **Step 2: Verify build fails**

```bash
cd /Users/gal.lev/Clipboard
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | tail -10
```

Expected: errors about `Settings` and `AppAppearance` missing.

- [ ] **Step 3: Implement**

`/Users/gal.lev/Clipboard/ClipboardManager/Settings.swift`:

```swift
// ClipboardManager/Settings.swift
import Foundation
import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Single source of truth for user-configurable settings persisted to
/// UserDefaults. Use this struct in coordinators / services where you want
/// to *read* the current values; use the matching `@AppStorage` property
/// wrappers in SwiftUI views where you want to *bind* a control to the
/// underlying default.
struct Settings: Sendable {

    enum Key {
        static let appearance = "appearance"
        static let historyLimit = "historyLimit"
        static let retentionDays = "retentionDays"
        static let showHoverPreview = "showHoverPreview"
        static let launchAtLogin = "launchAtLogin"   // tracked-only; service mgmt is source of truth
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var appearance: AppAppearance {
        get {
            AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "")
                ?? .system
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    var historyLimit: Int {
        get {
            let v = defaults.integer(forKey: Key.historyLimit)
            return v == 0 ? 5000 : v
        }
        nonmutating set { defaults.set(newValue, forKey: Key.historyLimit) }
    }

    var retentionDays: Int {
        get {
            let v = defaults.integer(forKey: Key.retentionDays)
            return v == 0 ? 90 : v
        }
        nonmutating set { defaults.set(newValue, forKey: Key.retentionDays) }
    }

    var showHoverPreview: Bool {
        get {
            if defaults.object(forKey: Key.showHoverPreview) == nil { return true }
            return defaults.bool(forKey: Key.showHoverPreview)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.showHoverPreview) }
    }
}

// MARK: - Launch-at-login helper (SMAppService, macOS 13+)

import ServiceManagement

enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggles. Returns the new state. Throws if SMAppService rejects the
    /// change (rare in practice).
    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> Bool {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return isEnabled
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

Tests take ~90s. Expected: 74 tests (66 + 8 new).

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Settings.swift ClipboardManagerTests/SettingsTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "settings: typed @AppStorage facade + LaunchAtLogin helper"
```

---

## Task 2: Refactor MenuBarController to show a dropdown menu

Currently left-click toggles the drawer. New behaviour:
- Left-click → dropdown menu (Open Clipboard / Preferences… / Quit)
- The global `⌘⇧V` hotkey still toggles the drawer
- The dropdown's "Open Clipboard" item also toggles the drawer

**Files:**
- Modify: `ClipboardManager/UI/MenuBar/MenuBarController.swift`

- [ ] **Step 1: Replace the file**

Read the current `/Users/gal.lev/Clipboard/ClipboardManager/UI/MenuBar/MenuBarController.swift` first.

Replace with:

```swift
// ClipboardManager/UI/MenuBar/MenuBarController.swift
import AppKit

@MainActor
final class MenuBarController: NSObject {

    private let statusItem: NSStatusItem
    private let onOpenClipboard: @MainActor () -> Void
    private let onOpenPreferences: @MainActor () -> Void

    init(
        onOpenClipboard: @escaping @MainActor () -> Void,
        onOpenPreferences: @escaping @MainActor () -> Void
    ) {
        self.onOpenClipboard = onOpenClipboard
        self.onOpenPreferences = onOpenPreferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configure()
    }

    private func configure() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "doc.on.clipboard",
                            accessibilityDescription: "Clipboard Manager")
        image?.isTemplate = true
        button.image = image
        // Build the dropdown menu the status item presents on click.
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "Open Clipboard",
            action: #selector(openClipboardClicked),
            keyEquivalent: "v"
        )
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        menu.addItem(openItem)

        let prefsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferencesClicked),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Clipboard Manager",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openClipboardClicked() {
        Log.menuBar.info("menu: open clipboard")
        onOpenClipboard()
    }

    @objc private func openPreferencesClicked() {
        Log.menuBar.info("menu: preferences")
        onOpenPreferences()
    }

    @objc private func quitClicked() {
        Log.menuBar.info("menu: quit")
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: Build**

```bash
make build 2>&1 | tail -5
```

Build will FAIL because `AppCoordinator` is still constructing the controller with the old `onActivate:` parameter. That's expected — Task 3 covers it.

For now, briefly update AppCoordinator's init to use the new signature. Open `/Users/gal.lev/Clipboard/ClipboardManager/App/AppCoordinator.swift`. Find:

```swift
        self.menuBar = MenuBarController { drawer.toggle() }
```

Replace with:

```swift
        self.menuBar = MenuBarController(
            onOpenClipboard: { drawer.toggle() },
            onOpenPreferences: { /* wired in Task 3 */ }
        )
```

Rebuild:

```bash
make build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Test**

```bash
make test 2>&1 | tail -10
```

Expected: 74 tests still pass.

- [ ] **Step 4: Commit**

```bash
git add ClipboardManager/UI/MenuBar/MenuBarController.swift ClipboardManager/App/AppCoordinator.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "menu-bar: dropdown (Open Clipboard / Preferences… / Quit)"
```

---

## Task 3: PreferencesView + window + panes

This task creates the SwiftUI preferences root, the NSWindow that hosts it, and both pane views in one cohesive change. Tested manually because pure UI.

**Files:**
- Create: `ClipboardManager/UI/Preferences/PreferencesWindowController.swift`
- Create: `ClipboardManager/UI/Preferences/PreferencesView.swift`
- Create: `ClipboardManager/UI/Preferences/GeneralPane.swift`
- Create: `ClipboardManager/UI/Preferences/ShortcutsPane.swift`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p /Users/gal.lev/Clipboard/ClipboardManager/UI/Preferences
```

- [ ] **Step 2: PreferencesView.swift**

```swift
// ClipboardManager/UI/Preferences/PreferencesView.swift
import SwiftUI

enum PreferencesPane: String, CaseIterable, Identifiable {
    case general
    case shortcuts

    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        }
    }
}

struct PreferencesView: View {
    @State private var selected: PreferencesPane = .general

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
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .navigationTitle(selected.label)
        }
    }
}

#Preview {
    PreferencesView()
        .frame(width: 600, height: 400)
}
```

- [ ] **Step 3: GeneralPane.swift**

```swift
// ClipboardManager/UI/Preferences/GeneralPane.swift
import SwiftUI

struct GeneralPane: View {
    @AppStorage(Settings.Key.appearance) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(Settings.Key.historyLimit) private var historyLimit: Int = 5000
    @AppStorage(Settings.Key.retentionDays) private var retentionDays: Int = 90
    @AppStorage(Settings.Key.showHoverPreview) private var showHoverPreview: Bool = true

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

- [ ] **Step 4: ShortcutsPane.swift**

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

            Section {
                Text("Click a shortcut and press the keys you want. Click the **×** to clear.")
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

- [ ] **Step 5: PreferencesWindowController.swift**

```swift
// ClipboardManager/UI/Preferences/PreferencesWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController {

    private var window: NSWindow?

    /// Brings the preferences window to the front, creating it if necessary.
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: PreferencesView())
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
        token = center.addObserver(forName: NSWindow.willCloseNotification, object: newWindow, queue: .main) { [weak self] _ in
            if let token { center.removeObserver(token) }
            NSApp.setActivationPolicy(.accessory)
            self?.window = nil
        }
    }
}
```

- [ ] **Step 6: Build**

```bash
xcodegen generate && make build 2>&1 | tail -8
```

Expected: `** BUILD SUCCEEDED **`. If the SwiftUI compiler complains about the Form view's complexity, split each Section into a private computed View. Use that as the escape hatch.

If `KeyboardShortcuts.Recorder` initializer takes a `String` for the label but in your installed version it takes a `LocalizedStringKey`, swap to the LocalizedStringKey form (it's overloaded).

- [ ] **Step 7: Tests still pass**

```bash
make test 2>&1 | tail -10
```

Expected: 74 tests pass.

- [ ] **Step 8: Commit**

```bash
git add ClipboardManager/UI/Preferences/
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "ui: preferences window with General + Shortcuts panes"
```

---

## Task 4: AppCoordinator owns PreferencesWindowController + applies appearance

**Files:**
- Modify: `ClipboardManager/App/AppCoordinator.swift`

- [ ] **Step 1: Read the current file** to confirm structure.

- [ ] **Step 2: Modify**

Add a `preferencesWindow` stored property, construct it in init, and wire the menu bar's Preferences action. Also apply the saved appearance once at start.

The new init body (preserving existing setup, only adding):

```swift
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

        // NEW: capture the preferences controller for the closure below.
        let prefs = self.preferencesWindow

        self.menuBar = MenuBarController(
            onOpenClipboard: { drawer.toggle() },
            onOpenPreferences: { prefs.show() }
        )
        self.hotkey = HotkeyService(
            onToggle: { drawer.toggle() },
            onScreenshot: { AppCoordinator.captureScreenshotToClipboard() }
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

        // Re-apply appearance if the user changes it in Preferences.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyAppearance() }
        }
    }

    private func applyAppearance() {
        let appearance = Settings().appearance
        NSApp.appearance = appearance.nsAppearance
    }
```

`captureScreenshotToClipboard()` is already present from Phase 3 — leave it untouched.

- [ ] **Step 3: Build + test**

```bash
make build 2>&1 | tail -5
make test 2>&1 | tail -10
```

Expected: build succeeds, 74 tests pass.

- [ ] **Step 4: Commit**

```bash
git add ClipboardManager/App/AppCoordinator.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "wire: coordinator opens preferences + applies appearance from Settings"
```

---

## Task 5: Wire RetentionJob and DrawerView hover toggle to Settings

**Files:**
- Modify: `ClipboardManager/Services/RetentionJob.swift`
- Modify: `ClipboardManager/UI/Drawer/DrawerView.swift`

- [ ] **Step 1: RetentionJob reads settings on each run**

Replace `/Users/gal.lev/Clipboard/ClipboardManager/Services/RetentionJob.swift` with:

```swift
// ClipboardManager/Services/RetentionJob.swift
import Foundation

@MainActor
final class RetentionJob {

    private let store: ClipboardStore
    private let settings: () -> Settings

    private var timer: Timer?

    /// `settings` is a closure so tests can inject a custom UserDefaults.
    init(store: ClipboardStore, settings: @escaping () -> Settings = { Settings() }) {
        self.store = store
        self.settings = settings
    }

    func start() {
        do { try runOnce() } catch { Log.app.error("retention initial pass: \(error.localizedDescription, privacy: .public)") }

        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                do { try self?.runOnce() } catch {
                    Log.app.error("retention pass: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One pass: age purge first, then count cap. Reads current limits from
    /// settings each time so changes apply on the next hourly tick.
    func runOnce() throws {
        let s = settings()
        // Int.max sentinel means "Forever" / "Unlimited" — skip that purge.
        if s.retentionDays != .max {
            try store.purgeOlderThan(days: s.retentionDays)
        }
        if s.historyLimit != .max {
            try store.purgeBeyondCount(max: s.historyLimit)
        }
    }
}
```

Note: the existing test `testRunPurgesByAgeAndCount` constructs `RetentionJob(store: store, retentionDays: 90, maxItems: 10)` — that's now invalid. We need to update the test too. Edit `/Users/gal.lev/Clipboard/ClipboardManagerTests/RetentionTests.swift`:

Replace its body with:

```swift
import XCTest
@testable import ClipboardManager

@MainActor
final class RetentionTests: XCTestCase {

    func testRunPurgesByAgeAndCount() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        try store.testingInsertStaleItem(
            body: "ancient",
            createdAt: Int64(Date().timeIntervalSince1970) - 86_400 * 200
        )
        for i in 0..<25 {
            _ = try store.recordText("item-\(i)", sourceApp: nil, sourceBundleId: nil)
        }
        // Custom settings instance with retentionDays=90 and historyLimit=10.
        let defaults = UserDefaults(suiteName: "retention-test-\(UUID().uuidString)")!
        defaults.set(90, forKey: Settings.Key.retentionDays)
        defaults.set(10, forKey: Settings.Key.historyLimit)
        let job = RetentionJob(store: store, settings: { Settings(defaults: defaults) })
        try job.runOnce()
        let remaining = try store.recentItems(limit: 100)
        XCTAssertEqual(remaining.count, 10)
        XCTAssertFalse(remaining.map(\.body).contains("ancient"))
    }
}
```

- [ ] **Step 2: DrawerView reads showHoverPreview**

Edit `/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/DrawerView.swift`. Add at the top of the struct alongside `accessibilityCheck`:

```swift
    @AppStorage(Settings.Key.showHoverPreview) private var showHoverPreview: Bool = true
```

Find the hover-preview overlay (the `if let hovered = debouncedHoveredItem` block inside `.overlay(alignment: .top)`). Wrap it:

```swift
        .overlay(alignment: .top) {
            if let hovered = debouncedHoveredItem, showHoverPreview {
                HoverPreviewContent(item: hovered)
                    .padding(.top, 56)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .animation(.easeOut(duration: 0.18), value: debouncedHoveredItem?.id)
            }
        }
```

If you want to be polite, also `.onHover` should NOT schedule the timer when `showHoverPreview` is false:

```swift
                            .onHover { hovering in
                                guard showHoverPreview else { return }
                                hoverTimer?.cancel()
                                // ... existing body ...
                            }
```

- [ ] **Step 3: Build + test**

```bash
make test 2>&1 | tail -10
```

Expected: 74 tests still pass.

- [ ] **Step 4: Commit**

```bash
git add ClipboardManager/Services/RetentionJob.swift ClipboardManagerTests/RetentionTests.swift ClipboardManager/UI/Drawer/DrawerView.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "wire: RetentionJob + DrawerView consume live Settings"
```

---

## Task 6: Smoke verify + tag v0.4.1

- [ ] **Step 1: Rebuild + relaunch**

```bash
cd /Users/gal.lev/Clipboard
killall ClipboardManager 2>/dev/null; sleep 1
make build 2>&1 | tail -3
APP_DIR=$(xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/ {print $3; exit}')
open -g "$APP_DIR/ClipboardManager.app"
```

- [ ] **Step 2: User verification** (ask Gal to verify):
  1. Left-click the menu bar clipboard icon → see dropdown: Open Clipboard / Preferences… / Quit.
  2. Click **Preferences…** → window opens with sidebar (General / Shortcuts).
  3. In General: toggle Launch at Login, switch Theme to Light/Dark/System (should apply immediately), change history limit, toggle Show preview on hover.
  4. In Shortcuts: click the recorder next to "Toggle Clipboard Drawer" → press a different key combo (e.g. `⌘⌥V`) → the global hotkey re-binds immediately. Then re-bind back to ⌘⇧V.
  5. Quit Preferences. Restart the app. Settings persist.
  6. Confirm "Open Clipboard" in the dropdown still toggles the drawer; `⌘⇧V` still toggles it.

- [ ] **Step 3: Tag**

```bash
git tag -a v0.4.1 -m "Settings window v1: General + Shortcuts panes, menu-bar dropdown"
git log --oneline v0.4.0-phase4..v0.4.1 2>/dev/null || git log --oneline -10
```

## Done criteria

- [ ] `make test` passes (74 tests).
- [ ] Menu bar dropdown works (Open Clipboard / Preferences… / Quit).
- [ ] Preferences window opens, both panes render, all controls function.
- [ ] Hotkeys rebind from the Shortcuts pane and take effect immediately.
- [ ] Settings persist across launches.
- [ ] Drawer's hover preview can be disabled.
- [ ] `v0.4.1` tag exists.

## What's next

Phase 5: snippets (pin items, snippet library, keyword expansion). The Pinned tab will go live and a new snippets pane will be added to Preferences in the same arc.
