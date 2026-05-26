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
