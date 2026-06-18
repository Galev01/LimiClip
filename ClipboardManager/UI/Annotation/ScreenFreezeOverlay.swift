// ClipboardManager/UI/Annotation/ScreenFreezeOverlay.swift
import AppKit
import SwiftUI

/// Borderless, top-level window that covers a screen. Key-capable so the
/// editor's key monitor (⌘C / ⌘S / ⌘⇧S / Esc) works.
final class ScreenFreezeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Flattens the selected region of a frozen screen capture plus its annotations
/// into PNG bytes. `selectionView` is in view points; `scale` is the screen's
/// backing factor (so the crop is taken at native pixel resolution).
enum ScreenFreezeFlatten {
    static func flatten(full: NSImage, selectionView: CGRect, scale: CGFloat,
                        annotations: [Annotation]) -> Data? {
        guard selectionView.width >= 1, selectionView.height >= 1,
              let cg = full.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let pixel = ScreenCaptureGeometry.pixelRect(viewRect: selectionView, scale: scale).integral
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let clamped = pixel.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1,
              let cropped = cg.cropping(to: clamped) else { return nil }
        let base = NSImage(cgImage: cropped,
                           size: NSSize(width: cropped.width, height: cropped.height))
        let shifted = annotations.map { ann -> Annotation in
            var a = ann
            a.points = ann.points.map {
                ScreenCaptureGeometry.toSelectionPixels($0, selectionOrigin: selectionView.origin, scale: scale)
            }
            return a
        }
        return try? ImageAnnotator.flatten(base: base, annotations: shifted)
    }
}

// MARK: - Phase 1: live region selection (screen NOT yet frozen)

/// A transparent full-screen overlay (pure AppKit) that dims the live screen
/// and lets the user drag-select a region. AppKit mouse handling is used rather
/// than SwiftUI gestures because a borderless, fully-transparent window does not
/// reliably deliver SwiftUI drags. Coordinates are top-left origin (isFlipped)
/// to match the capture and the annotation overlay. On mouse-up it reports the
/// region in view points; the screen is captured only afterwards, by the caller.
final class SelectionOverlayNSView: NSView {
    var onSelected: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var start: CGPoint?
    private var current: CGPoint?
    private var keyMonitor: Any?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Show a crosshair over the whole overlay so it's obvious we're in capture
    /// mode (matches the native screenshot cursor). Auto-reverts when the
    /// overlay closes (the cursor rect goes away with the view).
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selRect: CGRect {
        guard let s = start, let c = current else { return .zero }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    override func mouseDown(with e: NSEvent) {
        Log.app.info("screen freeze: selection mouseDown")
        NSCursor.crosshair.set()
        start = convert(e.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        NSCursor.crosshair.set()
        current = convert(e.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        current = convert(e.locationInWindow, from: nil)
        let r = selRect
        if r.width > 5, r.height > 5 {
            Log.app.info("screen freeze: selection complete \(Int(r.width), privacy: .public)x\(Int(r.height), privacy: .public)")
            onSelected?(r)
        } else {
            start = nil; current = nil; needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, keyMonitor == nil {
            NSCursor.crosshair.set()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                if e.keyCode == 53 { self?.onCancel?(); return nil }   // Esc
                return e
            }
        } else if window == nil, let m = keyMonitor {
            NSEvent.removeMonitor(m); keyMonitor = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim the whole (transparent) overlay so the live screen shows through
        // darkened, then punch the selection back to fully transparent + border.
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        let r = selRect
        if r.width > 0, r.height > 0 {
            NSColor.clear.set()
            r.fill(using: .copy)               // clears to transparent (live screen)
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let path = NSBezierPath(rect: r); path.lineWidth = 1.5; path.stroke()
        } else {
            let hint = "Drag to select an area  ·  Esc to cancel"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let size = (hint as NSString).size(withAttributes: attrs)
            (hint as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: 36), withAttributes: attrs)
        }
    }
}

// MARK: - Phase 2: annotate the frozen region in place

/// Shows the frozen full-screen capture dimmed except for the chosen region,
/// lets the user draw on that region, and docks a tool drawer to it.
struct ScreenFreezeView: View {
    let full: NSImage
    let viewSize: CGSize     // screen size in points
    let scale: CGFloat       // backing scale factor
    let selRect: CGRect      // selected region, view points
    var onCopy: (Data) -> Void
    var onSaveToFolder: (Data) -> Void
    var onSaveToHistory: (Data) -> Void
    var onClose: () -> Void

    @State private var annotations: [Annotation] = []
    @State private var draft: Annotation?
    @State private var tool: AnnotationTool = .pen
    @State private var color: Color = Color(hex: "#FF3B30") ?? .red
    @State private var lineWidth: CGFloat = 4
    @State private var pendingTextPoint: CGPoint?
    @State private var pendingText: String = ""
    @State private var showingText = false
    @State private var keyMonitor: Any?

    private let space = "freeze"
    private var colorHex: String { color.toHex() ?? "#FF3B30" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: full)
                .resizable()
                .frame(width: viewSize.width, height: viewSize.height)

            // Dim everything except the selection.
            Canvas { ctx, size in
                var path = Path(CGRect(origin: .zero, size: size))
                path.addRect(selRect)
                ctx.fill(path, with: .color(.black.opacity(0.35)), style: FillStyle(eoFill: true))
            }
            .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: selRect.width, height: selRect.height)
                .offset(x: selRect.minX, y: selRect.minY)
                .allowsHitTesting(false)

            Canvas { ctx, _ in
                for a in annotations { draw(a, in: &ctx) }
                if let draft { draw(draft, in: &ctx) }
            }
            .frame(width: viewSize.width, height: viewSize.height)
            .allowsHitTesting(false)

            // Drawing gesture layer, only over the selection.
            Color.clear.contentShape(Rectangle())
                .frame(width: selRect.width, height: selRect.height)
                .offset(x: selRect.minX, y: selRect.minY)
                .gesture(annotationDrag)

            toolDrawer.position(drawerPosition())
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .coordinateSpace(name: space)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .alert("Add Text", isPresented: $showingText) {
            TextField("Text", text: $pendingText)
            Button("Cancel", role: .cancel) { pendingTextPoint = nil }
            Button("Add") { commitText() }
        }
    }

    // MARK: - Gesture

    private var annotationDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { v in
                guard tool != .text else { return }
                let p = clamp(v.location)
                switch tool {
                case .pen:
                    if draft == nil {
                        draft = Annotation(id: UUID(), tool: .pen, points: [p], text: "",
                                           colorHex: colorHex, lineWidth: lineWidth)
                    } else { draft?.points.append(p) }
                case .arrow, .rectangle:
                    let start = draft?.points.first ?? p
                    draft = Annotation(id: UUID(), tool: tool, points: [start, p], text: "",
                                       colorHex: colorHex, lineWidth: lineWidth)
                case .text: break
                }
            }
            .onEnded { v in
                if tool == .text {
                    pendingTextPoint = clamp(v.location); pendingText = ""; showingText = true
                    return
                }
                if let d = draft { annotations.append(d) }
                draft = nil
            }
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, selRect.minX), selRect.maxX),
                y: min(max(p.y, selRect.minY), selRect.maxY))
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func commitText() {
        guard let pt = pendingTextPoint, !pendingText.isEmpty else { pendingTextPoint = nil; return }
        annotations.append(Annotation(id: UUID(), tool: .text, points: [pt], text: pendingText,
                                      colorHex: colorHex, lineWidth: lineWidth))
        pendingTextPoint = nil; pendingText = ""
    }

    // MARK: - Tool drawer

    private var toolDrawer: some View {
        HStack(spacing: 10) {
            Picker("", selection: $tool) {
                ForEach(AnnotationTool.allCases) { t in Text(t.rawValue.capitalized).tag(t) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 230)

            ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden()
            Slider(value: $lineWidth, in: 1...20).frame(width: 70)
            Button { if !annotations.isEmpty { annotations.removeLast() } } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(annotations.isEmpty)

            Divider().frame(height: 18)

            Button("Copy") { finish(onCopy) }
            Button("Save") { finish(onSaveToFolder) }
            Button("History") { finish(onSaveToHistory) }
            Button { onClose() } label: { Image(systemName: "xmark") }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .fixedSize()
    }

    private func drawerPosition() -> CGPoint {
        let w: CGFloat = 620, h: CGFloat = 46, gap: CGFloat = 12
        var y = selRect.maxY + gap + h / 2
        if y + h / 2 > viewSize.height { y = selRect.minY - gap - h / 2 }
        if y - h / 2 < 0 { y = viewSize.height - h / 2 - gap }
        let x = max(w / 2 + 8, min(selRect.midX, viewSize.width - w / 2 - 8))
        return CGPoint(x: x, y: y)
    }

    private func finish(_ callback: (Data) -> Void) {
        if let data = ScreenFreezeFlatten.flatten(full: full, selectionView: selRect,
                                                   scale: scale, annotations: annotations) {
            callback(data)
        }
        onClose()
    }

    // MARK: - Key monitor

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if showingText { return event }
            let cmd = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            let key = event.charactersIgnoringModifiers?.lowercased()
            if event.keyCode == 53 { onClose(); return nil }                       // Esc
            if cmd, !shift, key == "z" { if !annotations.isEmpty { annotations.removeLast() }; return nil }
            if cmd, !shift, key == "c" { finish(onCopy); return nil }
            if cmd, !shift, key == "s" { finish(onSaveToFolder); return nil }
            if cmd, shift, key == "s" { finish(onSaveToHistory); return nil }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: - Annotation preview (view-space points)

    private func draw(_ ann: Annotation, in ctx: inout GraphicsContext) {
        let c = Color(hex: ann.colorHex) ?? .red
        let pts = ann.points
        switch ann.tool {
        case .pen:
            guard pts.count >= 2 else { return }
            var path = Path(); path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(c), style: StrokeStyle(lineWidth: ann.lineWidth, lineCap: .round, lineJoin: .round))
        case .arrow:
            guard pts.count >= 2 else { return }
            let s = pts[0], e = pts[1]
            var path = Path(); path.move(to: s); path.addLine(to: e)
            let angle = atan2(e.y - s.y, e.x - s.x)
            let head = max(ann.lineWidth * 3, 10); let ha = CGFloat.pi / 6
            path.move(to: e); path.addLine(to: CGPoint(x: e.x - head * cos(angle - ha), y: e.y - head * sin(angle - ha)))
            path.move(to: e); path.addLine(to: CGPoint(x: e.x - head * cos(angle + ha), y: e.y - head * sin(angle + ha)))
            ctx.stroke(path, with: .color(c), style: StrokeStyle(lineWidth: ann.lineWidth, lineCap: .round, lineJoin: .round))
        case .rectangle:
            guard pts.count >= 2 else { return }
            let r = rect(pts[0], pts[1])
            ctx.stroke(Path(r), with: .color(c), style: StrokeStyle(lineWidth: ann.lineWidth, lineJoin: .round))
        case .text:
            guard let o = pts.first, !ann.text.isEmpty else { return }
            let fontSize = max(ann.lineWidth * 4, 8)
            ctx.draw(ctx.resolve(Text(ann.text).font(.system(size: fontSize)).foregroundColor(c)), at: o, anchor: .topLeading)
        }
    }
}
