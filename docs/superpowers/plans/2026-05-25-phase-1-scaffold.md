# Clipboard Manager — Phase 1 Implementation Plan (Scaffold)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a runnable, signed-by-development-team macOS menu-bar app whose `⌘⇧V` global hotkey toggles an empty bottom drawer that visually matches the design's drawer chrome (vibrancy, corner radius, shadow, spring animation). No clipboard data yet — that's Phase 2.

**Architecture:** Xcode project generated from `project.yml` via XcodeGen. App is `.accessory`-policy (menu-bar only, no Dock icon). `AppCoordinator` owns three things: `MenuBarController` (NSStatusItem), `HotkeyService` (via Sindre Sorhus's `KeyboardShortcuts` SPM package), and `DrawerWindow` (custom NSWindow at `.statusBar` level, full-screen-width, 300pt tall, anchored to the bottom of the active screen). Drawer body is a SwiftUI view hosted inside an `NSVisualEffectView` for the macOS vibrancy material.

**Tech Stack:** Swift 6, SwiftUI + AppKit, macOS 14.0 deployment target, XcodeGen for project file generation, Swift Package Manager for `KeyboardShortcuts` dependency, XCTest for unit tests.

**Verification target:** At the end of Phase 1, double-clicking the built app shows a clipboard icon in the menu bar, no Dock icon, no main app window; pressing `⌘⇧V` slides up a translucent rounded-top drawer at the bottom of the screen showing an empty-state "Your clipboard is empty" placeholder; pressing `⌘⇧V` again or `Esc` slides it back down.

---

## Pre-flight (one-time)

Run these checks before Task 1 — fix any failures before continuing.

```bash
# In project root: /Users/gal.lev/Clipboard

# macOS 14+ and Xcode 16+ required
sw_vers -productVersion      # expect >= 14.0  (you have 26.5 — fine)
xcodebuild -version          # expect Xcode 16+ (you have 26.5 — fine)

# Homebrew (needed for xcodegen)
which brew                   # if missing: install from https://brew.sh
```

---

## File Structure

This phase creates the following files. Subsequent phases will extend, not reorganize.

```
Clipboard/
├── project.yml                                   # XcodeGen config
├── Makefile                                      # convenience build targets
├── ClipboardManager/
│   ├── Info.plist                                # bundle metadata
│   ├── ClipboardManager.entitlements             # hardened runtime entitlements
│   ├── App/
│   │   ├── ClipboardManagerApp.swift             # @main, NSApplicationDelegate adapter
│   │   ├── AppDelegate.swift                     # app lifecycle
│   │   └── AppCoordinator.swift                  # ties services + UI together
│   ├── Services/
│   │   └── HotkeyService.swift                   # KeyboardShortcuts wrapper for ⌘⇧V
│   ├── UI/
│   │   ├── MenuBar/
│   │   │   └── MenuBarController.swift           # NSStatusItem + click handler
│   │   ├── Drawer/
│   │   │   ├── DrawerWindow.swift                # NSWindow subclass
│   │   │   ├── DrawerWindowController.swift      # animation + screen anchoring
│   │   │   ├── DrawerView.swift                  # SwiftUI root inside drawer
│   │   │   └── VisualEffectBackground.swift      # NSVisualEffectView SwiftUI bridge
│   │   ├── EmptyState.swift                      # "Your clipboard is empty"
│   │   └── DesignSystem/
│   │       ├── DesignColors.swift                # color tokens
│   │       ├── DesignTypography.swift            # font tokens
│   │       └── DesignMaterials.swift             # NSVisualEffectView material picker
│   ├── Logging.swift                             # os.Logger central config
│   └── Resources/
│       └── Assets.xcassets/
│           ├── AppIcon.appiconset/Contents.json  # placeholder icons (real ones later)
│           └── MenuBarIcon.imageset/Contents.json
└── ClipboardManagerTests/
    ├── DesignSystemTests.swift                   # token sanity
    ├── HotkeyServiceTests.swift                  # default shortcut
    └── DrawerGeometryTests.swift                 # screen-anchored frame math
```

Why this split: services are pure logic (testable); UI files are SwiftUI/AppKit (manually verified with previews); design system is one-file-per-concern; coordinator is the only place that knows about everything.

---

## Task 1: Install XcodeGen and create `project.yml`

**Files:**
- Create: `project.yml`
- Create: `.gitignore` additions

- [ ] **Step 1: Install XcodeGen**

```bash
brew install xcodegen
```

Expected: `xcodegen --version` prints a version (2.x or later).

- [ ] **Step 2: Update `.gitignore`** so generated Xcode project bits don't get committed

Append to the existing `/Users/gal.lev/Clipboard/.gitignore`:

```
# Generated Xcode project (regenerable from project.yml)
ClipboardManager.xcodeproj/
```

- [ ] **Step 3: Create `project.yml`** at the repo root

```yaml
name: ClipboardManager
options:
  deploymentTarget:
    macOS: "14.0"
  developmentLanguage: en
  createIntermediateGroups: true
  groupSortPosition: top
  generateEmptyDirectories: true

settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    PRODUCT_BUNDLE_IDENTIFIER: dev.gallev.ClipboardManager
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    ENABLE_HARDENED_RUNTIME: YES
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_IDENTITY: "-"
    ENABLE_USER_SCRIPT_SANDBOXING: NO
    ARCHS: "arm64 x86_64"
    ONLY_ACTIVE_ARCH: YES
    SWIFT_STRICT_CONCURRENCY: complete

packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.0.0"

targets:
  ClipboardManager:
    type: application
    platform: macOS
    sources:
      - path: ClipboardManager
        excludes:
          - "**/.DS_Store"
    resources:
      - path: ClipboardManager/Resources/Assets.xcassets
    info:
      path: ClipboardManager/Info.plist
      properties:
        CFBundleName: $(PRODUCT_NAME)
        CFBundleDisplayName: Clipboard Manager
        CFBundleIdentifier: $(PRODUCT_BUNDLE_IDENTIFIER)
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        CFBundlePackageType: APPL
        LSMinimumSystemVersion: $(MACOSX_DEPLOYMENT_TARGET)
        LSUIElement: true
        NSHighResolutionCapable: true
        NSPrincipalClass: NSApplication
    entitlements:
      path: ClipboardManager/ClipboardManager.entitlements
      properties:
        com.apple.security.app-sandbox: false
    dependencies:
      - package: KeyboardShortcuts
    scheme:
      testTargets:
        - ClipboardManagerTests
      gatherCoverageData: true

  ClipboardManagerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: ClipboardManagerTests
    dependencies:
      - target: ClipboardManager
    settings:
      base:
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/ClipboardManager.app/Contents/MacOS/ClipboardManager"
```

- [ ] **Step 4: Create source directory skeleton** so XcodeGen has something to scan

```bash
mkdir -p ClipboardManager/{App,Services,UI/{MenuBar,Drawer,DesignSystem},Resources/Assets.xcassets}
mkdir -p ClipboardManagerTests
```

- [ ] **Step 5: Create placeholder Info.plist and entitlements** so XcodeGen doesn't choke

`ClipboardManager/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

(XcodeGen will merge the `info.properties` block over this on every generate, so the dict-only stub is fine.)

`ClipboardManager/ClipboardManager.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 6: Add a stub Swift file** so XcodeGen creates a non-empty target

`ClipboardManager/App/ClipboardManagerApp.swift`:

```swift
import SwiftUI

@main
struct ClipboardManagerApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 7: Add a stub test file**

`ClipboardManagerTests/ClipboardManagerTests.swift`:

```swift
import XCTest

final class ClipboardManagerTests: XCTestCase {
    func testSanity() { XCTAssertEqual(1 + 1, 2) }
}
```

- [ ] **Step 8: Add asset catalog scaffolding**

`ClipboardManager/Resources/Assets.xcassets/Contents.json`:

```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`ClipboardManager/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 9: Generate the Xcode project**

```bash
cd /Users/gal.lev/Clipboard
xcodegen generate
```

Expected: prints `Created project at .../ClipboardManager.xcodeproj`.

- [ ] **Step 10: Build to verify the scaffold compiles**

```bash
xcodebuild -project ClipboardManager.xcodeproj \
  -scheme ClipboardManager \
  -configuration Debug \
  -destination "platform=macOS" \
  build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **` appears in last 20 lines.

- [ ] **Step 11: Run the test target** to verify it wires up

```bash
xcodebuild -project ClipboardManager.xcodeproj \
  -scheme ClipboardManager \
  -destination "platform=macOS" \
  test 2>&1 | tail -10
```

Expected: `Test Suite 'ClipboardManagerTests' passed`, exit code 0.

- [ ] **Step 12: Commit**

```bash
git add project.yml .gitignore ClipboardManager/ ClipboardManagerTests/
git commit -m "scaffold: xcodegen project, app stub, test target"
```

---

## Task 2: Logging module

**Files:**
- Create: `ClipboardManager/Logging.swift`

- [ ] **Step 1: Create the logger** — a thin namespace over `os.Logger` so every file uses the same subsystem

```swift
// ClipboardManager/Logging.swift
import OSLog

enum Log {
    static let subsystem = "dev.gallev.ClipboardManager"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let drawer = Logger(subsystem: subsystem, category: "drawer")
    static let menuBar = Logger(subsystem: subsystem, category: "menu-bar")
    static let coordinator = Logger(subsystem: subsystem, category: "coordinator")
}
```

- [ ] **Step 2: Regenerate + build**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/Logging.swift
git commit -m "log: central os.Logger categories"
```

---

## Task 3: Design system — colors (TDD)

**Files:**
- Create: `ClipboardManager/UI/DesignSystem/DesignColors.swift`
- Create: `ClipboardManagerTests/DesignSystemTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ClipboardManagerTests/DesignSystemTests.swift
import XCTest
import SwiftUI
@testable import ClipboardManager

final class DesignSystemTests: XCTestCase {

    func testAccentDefaultIsSystemBlueLike() {
        // The default accent matches macOS system blue (#007AFF).
        // We accept either the system color or the explicit RGB.
        let accent = DesignColors.accent
        let nsColor = NSColor(accent)
        let rgb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        XCTAssertEqual(rgb.redComponent, 0.0, accuracy: 0.05)
        XCTAssertEqual(rgb.greenComponent, 122.0 / 255.0, accuracy: 0.05)
        XCTAssertEqual(rgb.blueComponent, 1.0, accuracy: 0.05)
    }

    func testSnippetTintIsPurple() {
        let nsColor = NSColor(DesignColors.snippetTint).usingColorSpace(.deviceRGB)!
        XCTAssertEqual(nsColor.redComponent, 175.0 / 255.0, accuracy: 0.05)
        XCTAssertEqual(nsColor.greenComponent, 82.0 / 255.0, accuracy: 0.05)
        XCTAssertEqual(nsColor.blueComponent, 222.0 / 255.0, accuracy: 0.05)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -15
```

Expected: `Cannot find 'DesignColors' in scope` build error.

- [ ] **Step 3: Implement** — values pulled from the design's tint map and accent

```swift
// ClipboardManager/UI/DesignSystem/DesignColors.swift
import SwiftUI

enum DesignColors {
    static let accent = Color(red: 0, green: 122.0 / 255.0, blue: 1.0)            // #007AFF
    static let imageTint = Color(red: 0, green: 122.0 / 255.0, blue: 1.0).opacity(0.08)
    static let fileTint = Color(red: 1.0, green: 149.0 / 255.0, blue: 0).opacity(0.08)
    static let snippetTint = Color(red: 175.0 / 255.0, green: 82.0 / 255.0, blue: 222.0 / 255.0)

    // Surfaces (dark / light) used by cards and panels.
    static func cardBackground(dark: Bool) -> Color {
        dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.72)
    }

    static func hairline(dark: Bool) -> Color {
        dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }
}
```

- [ ] **Step 4: Run tests** — should pass

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `Test Suite 'DesignSystemTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/UI/DesignSystem/DesignColors.swift ClipboardManagerTests/DesignSystemTests.swift
git commit -m "design: color tokens (accent, tints, surfaces)"
```

---

## Task 4: Design system — typography

**Files:**
- Create: `ClipboardManager/UI/DesignSystem/DesignTypography.swift`
- Modify: `ClipboardManagerTests/DesignSystemTests.swift`

- [ ] **Step 1: Add the failing test** — append to `DesignSystemTests.swift`

```swift
    func testTypographyExposesTitleAndBody() {
        // These exist as SwiftUI Font values; we just verify the helpers are reachable.
        _ = DesignTypography.cardBody
        _ = DesignTypography.cardCode
        _ = DesignTypography.drawerTitle
        _ = DesignTypography.snippetKeyword
    }
```

- [ ] **Step 2: Run, verify build fails** with "Cannot find 'DesignTypography'"

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/UI/DesignSystem/DesignTypography.swift
import SwiftUI

enum DesignTypography {
    // System font stack mirrors the design's CSS: SF Pro Display for titles,
    // SF Pro Text for body, SF Mono for code. SwiftUI's .system font resolves
    // to these on macOS automatically.

    static let drawerTitle = Font.system(size: 18, weight: .bold).leading(.tight)
    static let cardBody = Font.system(size: 12.5, weight: .regular).leading(.standard)
    static let cardCode = Font.system(size: 11.5, weight: .regular, design: .monospaced).leading(.standard)
    static let cardFooterApp = Font.system(size: 10.5, weight: .medium)
    static let cardFooterTime = Font.system(size: 10, weight: .regular)
    static let snippetTitle = Font.system(size: 11.5, weight: .semibold)
    static let snippetKeyword = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let emptyStateTitle = Font.system(size: 15, weight: .semibold)
    static let emptyStateBody = Font.system(size: 12, weight: .regular)
    static let kbdHint = Font.system(size: 10, weight: .medium)
}
```

- [ ] **Step 4: Run tests**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: passes.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/UI/DesignSystem/DesignTypography.swift ClipboardManagerTests/DesignSystemTests.swift
git commit -m "design: typography tokens (drawer + card + snippet)"
```

---

## Task 5: Design system — materials

**Files:**
- Create: `ClipboardManager/UI/DesignSystem/DesignMaterials.swift`
- Modify: `ClipboardManagerTests/DesignSystemTests.swift`

- [ ] **Step 1: Add failing test**

```swift
    func testDrawerMaterialMaps() {
        XCTAssertEqual(DesignMaterials.drawer(dark: true), .hudWindow)
        XCTAssertEqual(DesignMaterials.drawer(dark: false), .popover)
    }

    func testPopoverMaterialIsAlwaysPopover() {
        XCTAssertEqual(DesignMaterials.popover(dark: true), .popover)
        XCTAssertEqual(DesignMaterials.popover(dark: false), .popover)
    }
```

- [ ] **Step 2: Run, verify build fails**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/UI/DesignSystem/DesignMaterials.swift
import AppKit

enum DesignMaterials {
    /// Material for the bottom drawer container. Dark = .hudWindow (heavier,
    /// more opaque vibrancy that survives a dark wallpaper); light = .popover.
    static func drawer(dark: Bool) -> NSVisualEffectView.Material {
        dark ? .hudWindow : .popover
    }

    /// Material for hover popovers and dropdowns.
    static func popover(dark: Bool) -> NSVisualEffectView.Material {
        .popover
    }

    /// Material for the preferences sidebar.
    static func sidebar(dark: Bool) -> NSVisualEffectView.Material {
        .sidebar
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: passes.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/UI/DesignSystem/DesignMaterials.swift ClipboardManagerTests/DesignSystemTests.swift
git commit -m "design: material mappers (drawer, popover, sidebar)"
```

---

## Task 6: SwiftUI bridge for `NSVisualEffectView`

**Files:**
- Create: `ClipboardManager/UI/Drawer/VisualEffectBackground.swift`

- [ ] **Step 1: Implement** the SwiftUI wrapper

```swift
// ClipboardManager/UI/Drawer/VisualEffectBackground.swift
import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Drawer/VisualEffectBackground.swift
git commit -m "ui: NSVisualEffectView SwiftUI bridge"
```

---

## Task 7: Empty state view

**Files:**
- Create: `ClipboardManager/UI/EmptyState.swift`

- [ ] **Step 1: Implement** — matches `screens.jsx` `EmptyState`

```swift
// ClipboardManager/UI/EmptyState.swift
import SwiftUI

struct EmptyStateView: View {
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.primary.opacity(0.2))

            Text("Your clipboard is empty")
                .font(DesignTypography.emptyStateTitle)
                .foregroundStyle(.primary.opacity(dark ? 0.35 : 0.3))

            Text("Copy something to get started. Text, images, and files will appear here automatically.")
                .font(DesignTypography.emptyStateBody)
                .foregroundStyle(.primary.opacity(dark ? 0.2 : 0.18))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView()
        .frame(width: 800, height: 300)
        .background(VisualEffectBackground(material: .hudWindow))
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/EmptyState.swift
git commit -m "ui: empty state view"
```

---

## Task 8: Drawer root SwiftUI view

**Files:**
- Create: `ClipboardManager/UI/Drawer/DrawerView.swift`

- [ ] **Step 1: Implement** the SwiftUI root that the drawer window hosts

```swift
// ClipboardManager/UI/Drawer/DrawerView.swift
import SwiftUI

struct DrawerView: View {
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            // Vibrancy material under everything.
            VisualEffectBackground(material: DesignMaterials.drawer(dark: dark))

            // Gradient overlay matches the prototype's drawer body.
            LinearGradient(
                colors: dark
                    ? [Color(red: 52/255, green: 52/255, blue: 56/255).opacity(0.97),
                       Color(red: 32/255, green: 32/255, blue: 35/255).opacity(0.99)]
                    : [Color(red: 248/255, green: 248/255, blue: 252/255).opacity(0.97),
                       Color(red: 240/255, green: 240/255, blue: 245/255).opacity(0.99)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Phase 1: empty state placeholder. Phase 4 will replace this with
            // the top bar + card strip + bottom count bar.
            EmptyStateView()
        }
        .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
        .ignoresSafeArea()
    }
}

#Preview {
    DrawerView()
        .frame(width: 1440, height: 300)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerView.swift
git commit -m "ui: drawer root view with vibrancy + gradient overlay"
```

---

## Task 9: Drawer window (NSWindow subclass)

**Files:**
- Create: `ClipboardManager/UI/Drawer/DrawerWindow.swift`

- [ ] **Step 1: Implement** the borderless, always-on-top, all-spaces window

```swift
// ClipboardManager/UI/Drawer/DrawerWindow.swift
import AppKit
import SwiftUI

final class DrawerWindow: NSPanel {
    static let drawerHeight: CGFloat = 300

    init() {
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

        let host = NSHostingView(rootView: DrawerView())
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
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Esc dismisses; handled by controller.
        if event.keyCode == 53 {
            NotificationCenter.default.post(name: .drawerDismissRequested, object: nil)
            return
        }
        super.keyDown(with: event)
    }
}

extension Notification.Name {
    static let drawerDismissRequested = Notification.Name("DrawerDismissRequested")
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerWindow.swift
git commit -m "ui: borderless full-spaces drawer NSPanel"
```

---

## Task 10: Drawer geometry helper (TDD)

**Files:**
- Create: `ClipboardManager/UI/Drawer/DrawerGeometry.swift`
- Create: `ClipboardManagerTests/DrawerGeometryTests.swift`

The drawer must sit flush against the bottom edge of the active screen, spanning the full screen width, with menu-bar + Dock taken into account when computing the on-screen vs off-screen frames.

- [ ] **Step 1: Failing test**

```swift
// ClipboardManagerTests/DrawerGeometryTests.swift
import XCTest
@testable import ClipboardManager

final class DrawerGeometryTests: XCTestCase {

    func testOnScreenFrameSpansScreenAndSitsAtBottom() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let f = DrawerGeometry.onScreenFrame(in: screen, height: 300)
        XCTAssertEqual(f.origin.x, 0)
        XCTAssertEqual(f.origin.y, 0)
        XCTAssertEqual(f.size.width, 1440)
        XCTAssertEqual(f.size.height, 300)
    }

    func testOffScreenFrameIsBelowScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let f = DrawerGeometry.offScreenFrame(in: screen, height: 300)
        XCTAssertEqual(f.origin.x, 0)
        XCTAssertEqual(f.origin.y, -300)
        XCTAssertEqual(f.size.width, 1440)
        XCTAssertEqual(f.size.height, 300)
    }

    func testFramesUseProvidedHeight() {
        let screen = CGRect(x: 100, y: 200, width: 1000, height: 800)
        let on = DrawerGeometry.onScreenFrame(in: screen, height: 250)
        XCTAssertEqual(on.origin, CGPoint(x: 100, y: 200))
        XCTAssertEqual(on.size, CGSize(width: 1000, height: 250))
    }
}
```

- [ ] **Step 2: Run, verify fails**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/UI/Drawer/DrawerGeometry.swift
import CoreGraphics

enum DrawerGeometry {
    /// Frame to use when the drawer is fully visible: full-width, anchored
    /// to the bottom edge of the screen's visible area.
    static func onScreenFrame(in screen: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: screen.origin.x, y: screen.origin.y, width: screen.size.width, height: height)
    }

    /// Frame to use when the drawer is offscreen (slid down). One full
    /// drawer-height below the visible area.
    static func offScreenFrame(in screen: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: screen.origin.x, y: screen.origin.y - height, width: screen.size.width, height: height)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `Test Suite 'DrawerGeometryTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerGeometry.swift ClipboardManagerTests/DrawerGeometryTests.swift
git commit -m "drawer: on/offscreen frame geometry helpers + tests"
```

---

## Task 11: Drawer window controller (animation)

**Files:**
- Create: `ClipboardManager/UI/Drawer/DrawerWindowController.swift`

This owns the window's lifecycle and animates it on/off screen.

- [ ] **Step 1: Implement**

```swift
// ClipboardManager/UI/Drawer/DrawerWindowController.swift
import AppKit

final class DrawerWindowController {
    private let window = DrawerWindow()
    private(set) var isVisible: Bool = false

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDismissRequest),
            name: .drawerDismissRequested, object: nil
        )
    }

    @objc private func handleDismissRequest() { hide() }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            Log.drawer.error("no screen available")
            return
        }
        let visible = screen.visibleFrame  // excludes menu bar + Dock
        let off = DrawerGeometry.offScreenFrame(in: visible, height: DrawerWindow.drawerHeight)
        let on = DrawerGeometry.onScreenFrame(in: visible, height: DrawerWindow.drawerHeight)

        window.setFrame(off, display: false)
        window.orderFrontRegardless()
        window.makeKey()
        isVisible = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.5, 1.0)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(on, display: true)
        }
    }

    func hide() {
        guard isVisible else { return }
        guard let screen = window.screen ?? NSScreen.main else {
            window.orderOut(nil)
            isVisible = false
            return
        }
        let off = DrawerGeometry.offScreenFrame(in: screen.visibleFrame, height: DrawerWindow.drawerHeight)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.7, 0.4)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(off, display: true)
        }, completionHandler: { [weak self] in
            self?.window.orderOut(nil)
            self?.isVisible = false
        })
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerWindowController.swift
git commit -m "drawer: window controller with slide-up/down animations"
```

---

## Task 12: Hotkey service (TDD where it makes sense)

**Files:**
- Create: `ClipboardManager/Services/HotkeyService.swift`
- Create: `ClipboardManagerTests/HotkeyServiceTests.swift`

`KeyboardShortcuts` registers shortcuts under a typed `Name`. The default for our app is `⌘⇧V`.

- [ ] **Step 1: Failing test** — verify the shortcut name exists and has a default

```swift
// ClipboardManagerTests/HotkeyServiceTests.swift
import XCTest
import KeyboardShortcuts
@testable import ClipboardManager

final class HotkeyServiceTests: XCTestCase {

    func testToggleDrawerShortcutHasDefault() {
        let name = KeyboardShortcuts.Name.toggleDrawer
        let shortcut = KeyboardShortcuts.getShortcut(for: name)
        XCTAssertNotNil(shortcut, "toggleDrawer must ship with a default shortcut")
    }

    func testToggleDrawerDefaultIsCommandShiftV() {
        let name = KeyboardShortcuts.Name.toggleDrawer
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else {
            XCTFail("missing shortcut")
            return
        }
        XCTAssertTrue(shortcut.modifiers.contains(.command))
        XCTAssertTrue(shortcut.modifiers.contains(.shift))
        XCTAssertEqual(shortcut.key, .v)
    }
}
```

- [ ] **Step 2: Run, verify fails** ("Type 'KeyboardShortcuts.Name' has no member 'toggleDrawer'")

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/Services/HotkeyService.swift
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that toggles the bottom drawer. Default: ⌘⇧V.
    static let toggleDrawer = Self("toggleDrawer", default: .init(.v, modifiers: [.command, .shift]))
}

@MainActor
final class HotkeyService {
    private let onToggle: @MainActor () -> Void

    init(onToggle: @escaping @MainActor () -> Void) {
        self.onToggle = onToggle
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleDrawer) { [weak self] in
            Log.hotkey.info("toggleDrawer fired")
            self?.onToggle()
        }
    }

    func stop() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: passes.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Services/HotkeyService.swift ClipboardManagerTests/HotkeyServiceTests.swift
git commit -m "hotkey: KeyboardShortcuts-backed ⌘⇧V toggle"
```

---

## Task 13: Menu bar status item

**Files:**
- Create: `ClipboardManager/UI/MenuBar/MenuBarController.swift`

- [ ] **Step 1: Implement**

```swift
// ClipboardManager/UI/MenuBar/MenuBarController.swift
import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let onActivate: @MainActor () -> Void

    init(onActivate: @escaping @MainActor () -> Void) {
        self.onActivate = onActivate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configure()
    }

    private func configure() {
        guard let button = statusItem.button else { return }
        // Use a template SF Symbol; replaced by a custom asset later.
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")
        image?.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp])
    }

    @objc private func handleClick() {
        Log.menuBar.info("menu bar status item clicked")
        onActivate()
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/MenuBar/MenuBarController.swift
git commit -m "menu-bar: NSStatusItem with template clipboard icon"
```

---

## Task 14: App coordinator

**Files:**
- Create: `ClipboardManager/App/AppCoordinator.swift`

- [ ] **Step 1: Implement** — the only class that wires services together

```swift
// ClipboardManager/App/AppCoordinator.swift
import AppKit

@MainActor
final class AppCoordinator {
    private let menuBar: MenuBarController
    private let drawer = DrawerWindowController()
    private let hotkey: HotkeyService

    init() {
        // Pre-declare locals so the closures can capture `drawer` safely.
        let drawer = self.drawer

        self.menuBar = MenuBarController { drawer.toggle() }
        self.hotkey = HotkeyService { drawer.toggle() }
    }

    func start() {
        Log.coordinator.info("coordinator starting")
        hotkey.start()
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/App/AppCoordinator.swift
git commit -m "app: coordinator wires menu bar + hotkey + drawer"
```

---

## Task 15: App delegate + entry point

**Files:**
- Modify: `ClipboardManager/App/ClipboardManagerApp.swift`
- Create: `ClipboardManager/App/AppDelegate.swift`

- [ ] **Step 1: Replace** `ClipboardManagerApp.swift` (was a stub)

```swift
// ClipboardManager/App/ClipboardManagerApp.swift
import SwiftUI

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Headless: menu bar only, no Settings or main window.
        // Settings window will be added in Phase 7.
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 2: Create the delegate**

```swift
// ClipboardManager/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("ClipboardManager launched (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
        NSApp.setActivationPolicy(.accessory)  // menu-bar agent, no Dock icon
        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // never terminate when the (non-existent) main window closes
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -configuration Debug -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run tests** to make sure everything still compiles together

```bash
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/App/ClipboardManagerApp.swift ClipboardManager/App/AppDelegate.swift
git commit -m "app: AppDelegate, .accessory policy, coordinator boot"
```

---

## Task 16: Makefile for convenience

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create**

```makefile
# Makefile — convenience wrappers around xcodegen + xcodebuild

PROJECT  := ClipboardManager.xcodeproj
SCHEME   := ClipboardManager
DEST     := platform=macOS
CONFIG   := Debug

.PHONY: gen build test run clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination "$(DEST)" build

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination "$(DEST)" test

run: build
	@APP_PATH=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/ {print $$3; exit}'); \
	open "$$APP_PATH/$(SCHEME).app"

clean:
	rm -rf build/ DerivedData/
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
```

- [ ] **Step 2: Verify**

```bash
make build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "build: Makefile wrapping xcodegen + xcodebuild"
```

---

## Task 17: End-to-end smoke verification (manual)

**No file changes.** This is the human-in-the-loop check that Phase 1 actually works.

- [ ] **Step 1: Build and launch the app**

```bash
make run
```

- [ ] **Step 2: Verify menu-bar presence**

Expected: a clipboard icon appears in the top-right of the system menu bar. No Dock icon appears.

If a Dock icon appears: check `LSUIElement` is `true` in the built `Info.plist` (`plutil -p $(find $(xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -showBuildSettings | awk '/BUILT_PRODUCTS_DIR/ {print $3; exit}')/ClipboardManager.app -name Info.plist) | grep LSUIElement`).

- [ ] **Step 3: Grant accessibility if prompted**

`KeyboardShortcuts` registers global shortcuts via Carbon and does not need Accessibility, but the first global-hotkey registration on a new app may surface a one-time prompt on some macOS versions. If macOS asks, grant it.

- [ ] **Step 4: Press `⌘⇧V`**

Expected: a translucent drawer slides up from the bottom of the screen, ~300pt tall, full-screen-width, with a "Your clipboard is empty" message centered.

- [ ] **Step 5: Press `⌘⇧V` again**

Expected: the drawer slides down and disappears.

- [ ] **Step 6: Open drawer, press `Esc`**

Expected: drawer slides down.

- [ ] **Step 7: Click the menu-bar icon**

Expected: drawer toggles (same behavior as the hotkey for now — dropdown UI comes in a later phase).

- [ ] **Step 8: Quit the app**

Use the `xcrun killall` fallback since there's no quit menu yet:

```bash
killall ClipboardManager
```

- [ ] **Step 9: Tag the commit** so we can reference Phase 1 completion

```bash
git tag -a v0.1.0-phase1 -m "Phase 1: menu-bar scaffold with hotkey-toggled empty drawer"
git log --oneline -5
```

If anything in Steps 2–7 failed, debug **before** moving to Phase 2. Common pitfalls:

- **No drawer appears but hotkey fires:** check `Log.drawer` output via `log stream --predicate 'subsystem == "dev.gallev.ClipboardManager"' --level debug`. Likely a screen-frame issue.
- **Drawer appears at wrong vertical position:** the `visibleFrame` of a screen on macOS uses bottom-left origin and excludes the menu bar; our geometry assumes `origin.y` is the bottom of the visible area, which is correct.
- **Hotkey doesn't fire:** open System Settings → Keyboard → Keyboard Shortcuts to confirm no other app owns `⌘⇧V`.

---

## Phase 1 — Done criteria

All of these must be true to consider Phase 1 complete:

- [ ] `make build` succeeds with no warnings.
- [ ] `make test` runs and every test passes.
- [ ] Launching the built `.app` puts an icon in the menu bar and no icon in the Dock.
- [ ] `⌘⇧V` toggles the drawer with a visible slide animation.
- [ ] `Esc` dismisses the drawer.
- [ ] The drawer's corner radius, vibrancy material, and hairline border match the design (eyeball compare against `design/mac-clipboard-app/project/Clipboard Manager.html`).
- [ ] Phase 1 tag `v0.1.0-phase1` exists in git.

## What's next

Phase 2 — pasteboard pipeline. It adds: `ClipboardStore` (GRDB + SQLCipher), `PasteboardMonitor`, retention job, dedupe, privacy enforcement (concealed-type + app exclusions). The drawer becomes data-driven (text items only); cards arrive in Phase 3 (images + files).

I will write the Phase 2 plan only after we sign off on Phase 1 actually working end-to-end.
