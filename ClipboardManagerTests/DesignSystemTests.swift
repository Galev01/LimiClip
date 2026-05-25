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

    func testTypographyExposesTitleAndBody() {
        // These exist as SwiftUI Font values; we just verify the helpers are reachable.
        _ = DesignTypography.cardBody
        _ = DesignTypography.cardCode
        _ = DesignTypography.drawerTitle
        _ = DesignTypography.snippetKeyword
    }
}
