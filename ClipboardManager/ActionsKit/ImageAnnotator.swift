// ClipboardManager/ActionsKit/ImageAnnotator.swift
import Foundation
import AppKit

enum AnnotationTool: String, CaseIterable, Identifiable {
    case pen, arrow, rectangle, text
    var id: String { rawValue }
}

struct Annotation: Identifiable, Equatable {
    let id: UUID
    var tool: AnnotationTool
    var points: [CGPoint]      // pen: path; arrow/rect: [start, end]
    var text: String           // text tool only
    var colorHex: String       // e.g. "#FF3B30"
    var lineWidth: CGFloat
}

enum ImageAnnotator {

    enum Failure: Error { case noBitmap, encodeFailed }

    /// Composites `annotations` over `base` and returns PNG bytes.
    /// Coordinates in `annotations` are in the base image's pixel space.
    static func flatten(base: NSImage, annotations: [Annotation]) throws -> Data {
        let pixelSize = pixelSize(of: base)
        guard pixelSize.width > 0, pixelSize.height > 0 else { throw Failure.noBitmap }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw Failure.noBitmap }
        rep.size = NSSize(width: pixelSize.width, height: pixelSize.height)

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { throw Failure.noBitmap }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        let fullRect = NSRect(origin: .zero, size: NSSize(width: pixelSize.width, height: pixelSize.height))
        base.draw(in: fullRect,
                  from: NSRect(origin: .zero, size: base.size),
                  operation: .copy,
                  fraction: 1.0)

        for ann in annotations {
            draw(ann, in: pixelSize)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw Failure.encodeFailed
        }
        return data
    }

    // MARK: - Drawing

    private static func draw(_ ann: Annotation, in pixelSize: CGSize) {
        let color = colorFromHex(ann.colorHex)
        color.set()

        switch ann.tool {
        case .pen:
            guard ann.points.count >= 2 else { return }
            let path = NSBezierPath()
            path.lineWidth = ann.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: flip(ann.points[0], in: pixelSize))
            for pt in ann.points.dropFirst() {
                path.line(to: flip(pt, in: pixelSize))
            }
            path.stroke()

        case .arrow:
            guard ann.points.count >= 2 else { return }
            let start = flip(ann.points[0], in: pixelSize)
            let end = flip(ann.points[1], in: pixelSize)
            let line = NSBezierPath()
            line.lineWidth = ann.lineWidth
            line.lineCapStyle = .round
            line.move(to: start)
            line.line(to: end)
            line.stroke()

            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = max(ann.lineWidth * 3, 10)
            let headAngle = CGFloat.pi / 6
            let head = NSBezierPath()
            head.lineWidth = ann.lineWidth
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.move(to: end)
            head.line(to: CGPoint(x: end.x - headLength * cos(angle - headAngle),
                                  y: end.y - headLength * sin(angle - headAngle)))
            head.move(to: end)
            head.line(to: CGPoint(x: end.x - headLength * cos(angle + headAngle),
                                  y: end.y - headLength * sin(angle + headAngle)))
            head.stroke()

        case .rectangle:
            guard ann.points.count >= 2 else { return }
            let p0 = flip(ann.points[0], in: pixelSize)
            let p1 = flip(ann.points[1], in: pixelSize)
            let rect = NSRect(x: min(p0.x, p1.x), y: min(p0.y, p1.y),
                              width: abs(p1.x - p0.x), height: abs(p1.y - p0.y))
            let path = NSBezierPath(rect: rect)
            path.lineWidth = ann.lineWidth
            path.lineJoinStyle = .round
            path.stroke()

        case .text:
            guard let origin = ann.points.first, !ann.text.isEmpty else { return }
            let fontSize = max(ann.lineWidth * 4, 8)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: fontSize)
            ]
            let str = NSAttributedString(string: ann.text, attributes: attrs)
            str.draw(at: flip(origin, in: pixelSize))
        }
    }

    // MARK: - Helpers

    /// Annotation coordinates are top-left origin (view space); bitmap context
    /// is bottom-left origin. Flip the y axis into the bitmap's pixel space.
    private static func flip(_ point: CGPoint, in pixelSize: CGSize) -> CGPoint {
        CGPoint(x: point.x, y: pixelSize.height - point.y)
    }

    private static func pixelSize(of image: NSImage) -> CGSize {
        // The base image's logical (point) size defines the annotation pixel
        // space the caller works in; rep pixel dimensions may be Retina-scaled.
        if image.size.width > 0, image.size.height > 0 {
            return image.size
        }
        if let rep = image.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return .zero
    }

    private static func colorFromHex(_ hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return .red }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
