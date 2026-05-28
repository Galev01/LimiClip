import XCTest
import KeyboardShortcuts
@testable import ClipboardManager

final class HotkeyServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset any user-stored overrides so each test reads the compiled-in
        // default (or nil) — not whatever a running app instance persisted to
        // the shared UserDefaults domain (the test host shares the app's
        // bundle id, so live shortcut bindings would otherwise leak in).
        KeyboardShortcuts.reset(.toggleDrawer, .screenshotToClipboard, .toggleCompactPopup)
    }

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

    func testScreenshotShortcutHasDefault() {
        let name = KeyboardShortcuts.Name.screenshotToClipboard
        XCTAssertNotNil(KeyboardShortcuts.getShortcut(for: name))
    }

    func testScreenshotDefaultIsCommandShiftA() {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .screenshotToClipboard) else {
            XCTFail("missing shortcut")
            return
        }
        XCTAssertTrue(shortcut.modifiers.contains(.command))
        XCTAssertTrue(shortcut.modifiers.contains(.shift))
        XCTAssertEqual(shortcut.key, .a)
    }

    func testCompactPopupShortcutHasNoDefault() {
        XCTAssertNil(
            KeyboardShortcuts.getShortcut(for: .toggleCompactPopup),
            "toggleCompactPopup must ship with no default shortcut — user assigns it in Preferences"
        )
    }
}
