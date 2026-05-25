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
