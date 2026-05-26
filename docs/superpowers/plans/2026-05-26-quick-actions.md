# Quick Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect phone numbers, email addresses, and hex color codes in clipboard text items and surface one-tap actions (Call, Compose, Copy) in the context menu.

**Architecture:** Pure `QuickActionDetector` enum with static detect method returns an array of `QuickAction` cases. ClipboardCard reads detected actions and conditionally renders context menu items. No storage changes.

**Tech Stack:** Swift 6.0, SwiftUI context menu, NSRegularExpression / NSDataDetector, NSWorkspace.open

---

## File Structure

```
ClipboardManager/
└── ActionsKit/
    └── QuickActionDetector.swift          (NEW)

ClipboardManagerTests/
└── QuickActionDetectorTests.swift         (NEW)

ClipboardManager/UI/Drawer/
└── ClipboardCard.swift                    (MODIFIED — context menu additions)
```

---

## Pre-flight

```bash
cd /Users/gal.lev/Clipboard
git log --oneline -1
make test 2>&1 | tail -3
```

Expected: latest commit from master, all existing tests pass (currently ~74 tests).

---

## Task 1: QuickActionDetector (TDD)

Implement the detector using `NSDataDetector` for phone/email and `NSRegularExpression` for hex color. Write the tests first, then make them pass.

**Files:**
- Create: `ClipboardManager/ActionsKit/QuickActionDetector.swift`
- Create: `ClipboardManagerTests/QuickActionDetectorTests.swift`

### Step 1: Write failing tests

Create `/Users/gal.lev/Clipboard/ClipboardManagerTests/QuickActionDetectorTests.swift`:

```swift
// ClipboardManagerTests/QuickActionDetectorTests.swift
import XCTest
@testable import ClipboardManager

final class QuickActionDetectorTests: XCTestCase {

    // MARK: - Phone number detection

    func testDetectsUSPhone() {
        let actions = QuickActionDetector.detect(in: "+1 555 123 4567")
        XCTAssertEqual(actions.count, 1)
        if case .call(let number) = actions[0] {
            XCTAssertFalse(number.isEmpty)
        } else {
            XCTFail("Expected .call, got \(actions[0])")
        }
    }

    func testDetectsDashedPhone() {
        let actions = QuickActionDetector.detect(in: "555-123-4567")
        XCTAssertEqual(actions.count, 1)
        guard case .call = actions[0] else {
            XCTFail("Expected .call, got \(actions[0])"); return
        }
    }

    func testDetectsParenthesizedPhone() {
        let actions = QuickActionDetector.detect(in: "(555) 123-4567")
        XCTAssertEqual(actions.count, 1)
        guard case .call = actions[0] else {
            XCTFail("Expected .call, got \(actions[0])"); return
        }
    }

    func testPlainTextNotPhone() {
        XCTAssertEqual(QuickActionDetector.detect(in: "hello world"), [])
    }

    func testShortNumberNotPhone() {
        // Four-digit numbers must not trigger phone detection.
        XCTAssertEqual(QuickActionDetector.detect(in: "1234"), [])
    }

    // MARK: - Email detection

    func testDetectsEmail() {
        let actions = QuickActionDetector.detect(in: "user@example.com")
        XCTAssertEqual(actions.count, 1)
        if case .composeEmail(let address) = actions[0] {
            XCTAssertEqual(address, "user@example.com")
        } else {
            XCTFail("Expected .composeEmail, got \(actions[0])")
        }
    }

    func testDetectsEmailWithSubdomain() {
        let actions = QuickActionDetector.detect(in: "gal.lev@xmcyber.com")
        XCTAssertEqual(actions.count, 1)
        guard case .composeEmail(let address) = actions[0] else {
            XCTFail("Expected .composeEmail"); return
        }
        XCTAssertEqual(address, "gal.lev@xmcyber.com")
    }

    func testPlainTextNotEmail() {
        XCTAssertEqual(QuickActionDetector.detect(in: "hello world"), [])
    }

    func testURLSubtypeNotEmail() {
        // A bare URL should not be misclassified as an email.
        XCTAssertEqual(QuickActionDetector.detect(in: "https://example.com"), [])
    }

    // MARK: - Hex color detection

    func testDetectsFullHex() {
        let actions = QuickActionDetector.detect(in: "#FF5733")
        XCTAssertEqual(actions.count, 1)
        if case .copyHexColor(let hex) = actions[0] {
            XCTAssertEqual(hex, "#FF5733")
        } else {
            XCTFail("Expected .copyHexColor, got \(actions[0])")
        }
    }

    func testDetectsShortHex() {
        let actions = QuickActionDetector.detect(in: "#fff")
        XCTAssertEqual(actions.count, 1)
        if case .copyHexColor(let hex) = actions[0] {
            XCTAssertEqual(hex, "#fff")
        } else {
            XCTFail("Expected .copyHexColor, got \(actions[0])")
        }
    }

    func testNormalizesHexCase() {
        // Case is preserved as-is (no normalisation to uppercase).
        let actions = QuickActionDetector.detect(in: "#ff5733")
        XCTAssertEqual(actions.count, 1)
        if case .copyHexColor(let hex) = actions[0] {
            XCTAssertEqual(hex, "#ff5733")
        } else {
            XCTFail("Expected .copyHexColor, got \(actions[0])")
        }
    }

    func testPartialHexNotDetected() {
        // Embedded / partial hex must not match — only exact whole-string match.
        XCTAssertEqual(QuickActionDetector.detect(in: "some text #FF"), [])
        XCTAssertEqual(QuickActionDetector.detect(in: "#GGGGGG"), [])   // invalid chars
        XCTAssertEqual(QuickActionDetector.detect(in: "#12345"), [])    // 5-digit not valid
    }

    // MARK: - No false positives on subtypes handled elsewhere

    func testURLStringProducesNoActions() {
        // URL subtype is handled upstream by the .url subtype path; the
        // detector should see these only when subtype != .url, but even if it
        // did see them, the mailto: link is a mailto so should NOT produce
        // composeEmail — the subtype guard in ClipboardCard prevents this.
        // Here we just confirm the bare string doesn't produce an email action.
        XCTAssertEqual(QuickActionDetector.detect(in: "https://example.com"), [])
    }
}
```

### Step 2: Verify build fails

```bash
cd /Users/gal.lev/Clipboard
xcodegen generate && xcodebuild -project ClipboardManager.xcodeproj \
  -scheme ClipboardManager -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD"
```

Expected: compiler errors about `QuickActionDetector`, `QuickAction` missing.

### Step 3: Implement QuickActionDetector

Create `/Users/gal.lev/Clipboard/ClipboardManager/ActionsKit/QuickActionDetector.swift`:

```swift
// ClipboardManager/ActionsKit/QuickActionDetector.swift
import Foundation

// MARK: - QuickAction

/// A detected actionable entity in a clipboard text item.
enum QuickAction: Equatable, Sendable {
    /// A phone number. The associated value is the raw string
    /// returned by NSDataDetector (e.g. "+15551234567").
    case call(String)
    /// An email address exactly as it appears in the text.
    case composeEmail(String)
    /// A CSS-style hex color code in its original case (e.g. "#FF5733", "#fff").
    case copyHexColor(String)
}

// MARK: - QuickActionDetector

/// Stateless detector that analyses a text string and returns all actionable
/// entities found in it. Detection is intentionally conservative: a string
/// must be *almost entirely* the entity in question (≥ 60 % coverage for
/// phone/email) to avoid false positives on rich prose.
///
/// Call sites should already guard `item.subtype != TextSubtype.url.rawValue`
/// before invoking this — URL items are handled separately and are excluded
/// from detection here.
enum QuickActionDetector {

    // MARK: Public API

    /// Returns every `QuickAction` detected in `text`, in the order:
    /// phone → email → hex color.
    static func detect(in text: String) -> [QuickAction] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var actions: [QuickAction] = []

        if let phone = detectPhone(in: trimmed) {
            actions.append(.call(phone))
        }
        if let email = detectEmail(in: trimmed) {
            actions.append(.composeEmail(email))
        }
        if let hex = detectHexColor(in: trimmed) {
            actions.append(.copyHexColor(hex))
        }

        return actions
    }

    // MARK: - Phone detection

    /// Uses `NSDataDetector` with the `.phoneNumber` type. Accepts the text
    /// only when a single match spans ≥ 60 % of the trimmed string length,
    /// preventing stray digits in prose from being flagged.
    private static func detectPhone(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = detector.matches(in: text, options: [], range: range)

        guard matches.count == 1, let match = matches.first else { return nil }

        // Coverage heuristic: the match must span ≥ 60 % of the trimmed length.
        let coverage = Double(match.range.length) / Double(nsText.length)
        guard coverage >= 0.6 else { return nil }

        // Prefer the structured phone number if available; fall back to the
        // substring captured by the match range.
        if let phoneNumber = match.phoneNumber {
            return phoneNumber
        }
        return nsText.substring(with: match.range)
    }

    // MARK: - Email detection

    /// Uses `NSDataDetector` with the `.link` type, then filters for
    /// `mailto:` links. Same ≥ 60 % coverage heuristic as phone detection.
    private static func detectEmail(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = detector.matches(in: text, options: [], range: range)

        // Keep only mailto: matches.
        let emailMatches = matches.filter { $0.url?.scheme == "mailto" }
        guard emailMatches.count == 1, let match = emailMatches.first else { return nil }

        // Coverage heuristic.
        let coverage = Double(match.range.length) / Double(nsText.length)
        guard coverage >= 0.6 else { return nil }

        // Strip the "mailto:" prefix to get the bare address.
        if let url = match.url, let host = url.host {
            let user = url.user ?? nsText.substring(with: match.range)
                .replacingOccurrences(of: "mailto:", with: "")
                .components(separatedBy: "@").first ?? ""
            return user.isEmpty ? nsText.substring(with: match.range) : "\(user)@\(host)"
        }
        return nsText.substring(with: match.range)
            .replacingOccurrences(of: "mailto:", with: "")
    }

    // MARK: - Hex color detection

    /// Exact-match regex: the entire trimmed string must be `#` followed by
    /// exactly 3 or 6 hexadecimal characters. No coverage heuristic — the
    /// whole string must be the color code.
    private static let hexRegex: NSRegularExpression = {
        // Force-unwrap: the pattern is a compile-time constant.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")
    }()

    private static func detectHexColor(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard hexRegex.firstMatch(in: text, options: [], range: range) != nil else {
            return nil
        }
        return text
    }
}
```

### Step 4: Run tests

```bash
cd /Users/gal.lev/Clipboard
make test 2>&1 | tail -15
```

Expected: all previous tests pass plus the 12 new `QuickActionDetectorTests` pass. Total increases by 12.

If `testDetectsParenthesizedPhone` or `testDetectsDashedPhone` fail, open the detector and verify the `NSDataDetector` coverage calculation. The match range for `(555) 123-4567` (14 chars) vs `555-123-4567` (12 chars) should both satisfy the 60 % threshold because the full string is the phone number.

### Step 5: Commit

```bash
git add ClipboardManager/ActionsKit/QuickActionDetector.swift \
        ClipboardManagerTests/QuickActionDetectorTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" \
  commit -m "actions: QuickActionDetector — phone / email / hex color detection (TDD)"
```

---

## Task 2: Add quick actions to ClipboardCard context menu

Wire `QuickActionDetector` into the existing `.contextMenu` in `ClipboardCard`. No new card UI, no new files — this is a pure context-menu addition.

**Files:**
- Modify: `ClipboardManager/UI/Drawer/ClipboardCard.swift`

### Step 1: Read the current file

Read `/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/ClipboardCard.swift` to confirm the current context menu structure before editing.

The existing menu (lines 51–67 at time of writing):

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

### Step 2: Add the `quickActions` computed property

In `ClipboardCard`, add the following computed property alongside the existing private helpers (`isCode`, `isURL`, `isImage`, `isFile`):

```swift
private var quickActions: [QuickAction] {
    guard item.kind == "text", item.subtype != TextSubtype.url.rawValue else { return [] }
    return QuickActionDetector.detect(in: item.body)
}
```

Insert it immediately after the `isFile` property.

### Step 3: Extend the context menu

Replace the existing `.contextMenu { … }` block with the version below. The only change is a new conditional section inserted **after the Copy button and before the first Divider**:

```swift
.contextMenu {
    Button("Paste") { onPaste?(item, false) }
        .keyboardShortcut(.return, modifiers: [])
    Button("Paste as Plain Text") { onPaste?(item, true) }
        .keyboardShortcut(.return, modifiers: .shift)
    Button("Copy") { onCopy?(item) }
        .keyboardShortcut("c", modifiers: .command)

    // Quick actions — only present for plain/code/json text items where
    // an actionable entity is detected.
    if !quickActions.isEmpty {
        Divider()
        ForEach(Array(quickActions.enumerated()), id: \.offset) { _, action in
            switch action {
            case .call(let number):
                Button("Call \(number)") {
                    if let url = URL(string: "tel:\(number.filter { $0.isNumber || $0 == "+" })") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .composeEmail(let address):
                Button("Compose Email") {
                    if let url = URL(string: "mailto:\(address)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .copyHexColor(let hex):
                Button("Copy \(hex)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hex, forType: .string)
                }
                Button(action: {
                    if let url = URL(string: "https://www.color-hex.com/color/\(hex.dropFirst())") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label(hex, systemImage: "circle.fill")
                }
            }
        }
    }

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

### Step 4: Build

```bash
cd /Users/gal.lev/Clipboard
make build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

If the Swift compiler reports a warning about `switch` inside `ForEach` not being exhaustive or a type-checker timeout, extract the body into a `@ViewBuilder` helper:

```swift
@ViewBuilder
private func contextMenuItems(for action: QuickAction) -> some View {
    switch action {
    case .call(let number):
        Button("Call \(number)") {
            if let url = URL(string: "tel:\(number.filter { $0.isNumber || $0 == "+" })") {
                NSWorkspace.shared.open(url)
            }
        }
    case .composeEmail(let address):
        Button("Compose Email") {
            if let url = URL(string: "mailto:\(address)") {
                NSWorkspace.shared.open(url)
            }
        }
    case .copyHexColor(let hex):
        Button("Copy \(hex)") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
        }
        Button(action: {
            if let url = URL(string: "https://www.color-hex.com/color/\(hex.dropFirst())") {
                NSWorkspace.shared.open(url)
            }
        }) {
            Label(hex, systemImage: "circle.fill")
        }
    }
}
```

Then replace the `switch` inside `ForEach` with `contextMenuItems(for: action)`.

### Step 5: Run all tests

```bash
make test 2>&1 | tail -10
```

Expected: all tests pass. No new tests needed for the UI layer (pure wiring; logic is covered in Task 1).

### Step 6: Commit

```bash
git add ClipboardManager/UI/Drawer/ClipboardCard.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" \
  commit -m "ui: quick-action context menu items for phone / email / hex color"
```

---

## Done criteria

- [ ] `make test` passes (all existing tests + 12 new `QuickActionDetectorTests`).
- [ ] Right-clicking a card containing `+1 555 123 4567` shows a **Call** item in the context menu; tapping it opens the Phone app (or prompts on macOS).
- [ ] Right-clicking a card containing `user@example.com` shows **Compose Email**; tapping opens Mail.app.
- [ ] Right-clicking a card containing `#FF5733` shows **Copy #FF5733** and a **Label("#FF5733", systemImage: "circle.fill")** preview item.
- [ ] No new quick-action items appear for URL-subtype items, images, or file items.
- [ ] No new card UI elements were added (context menu only).
- [ ] No schema or storage changes were made.

## What's next

Phase 6 candidates: snippet library with keyword expansion (uses the pinned column already in the schema), or a compact inline preview for hex swatches rendered directly in the card body when the entire item is a hex color.
