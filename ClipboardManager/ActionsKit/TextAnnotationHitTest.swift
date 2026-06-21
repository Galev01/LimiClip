// ClipboardManager/ActionsKit/TextAnnotationHitTest.swift
import AppKit

/// Pure helpers for hit-testing movable/editable text-annotation labels.
/// Used by both editors (ScreenFreezeView and AnnotationCanvas) and exercised
/// by unit tests, so the methods are `nonisolated`.
enum TextAnnotationHitTest {

    /// Index of the TOPMOST (last-drawn) rect containing `point`, or nil.
    /// Indices map 1:1 to the input array; use `.null` for non-text slots.
    /// `CGRect.null.contains(_)` is false, so `.null` slots never match.
    nonisolated static func topmostIndex(rects: [CGRect], containing point: CGPoint) -> Int? {
        rects.enumerated()
            .filter { $0.element.contains(point) }
            .map(\.offset)
            .max()
    }

    /// Bounds of a label drawn from top-left `origin` at `fontSize`, padded.
    /// Measures the string via the system font; text is drawn with a
    /// `.topLeading` anchor, so bounds extend down/right from `origin`.
    nonisolated static func bounds(text: String, origin: CGPoint, fontSize: CGFloat, padding: CGFloat = 6) -> CGRect {
        let size = (text as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)])
        return CGRect(origin: origin, size: size).insetBy(dx: -padding, dy: -padding)
    }
}
