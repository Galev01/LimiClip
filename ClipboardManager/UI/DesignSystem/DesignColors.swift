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
