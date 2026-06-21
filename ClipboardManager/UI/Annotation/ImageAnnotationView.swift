// ClipboardManager/UI/Annotation/ImageAnnotationView.swift
import SwiftUI
import AppKit

/// The drawing surface: renders the base image, committed annotations, and the
/// in-progress draft. Translates view-space gestures into base pixel-space
/// coordinates so the flattened output (via `ImageAnnotator`) matches.
struct AnnotationCanvas: View {
    let base: NSImage
    @Binding var annotations: [Annotation]
    let tool: AnnotationTool
    let colorHex: String
    let lineWidth: CGFloat
    /// Called for the text tool: provides the base-space point of a tap so the
    /// host can prompt for a string.
    var onTextTap: (CGPoint) -> Void
    /// Called when an existing text label is tapped (not moved): asks the host
    /// to re-open the text prompt pre-filled for that annotation index.
    var onEditText: (Int) -> Void

    @State private var draft: Annotation?
    @State private var movingTextIndex: Int?
    @State private var dragStartLocation: CGPoint?
    @State private var didMoveText = false

    var body: some View {
        GeometryReader { geo in
            let fitted = fittedRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: base)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                Canvas { ctx, _ in
                    for ann in annotations {
                        draw(ann, in: &ctx, fitted: fitted)
                    }
                    if let draft {
                        draw(draft, in: &ctx, fitted: fitted)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleChanged(value, fitted: fitted)
                    }
                    .onEnded { value in
                        handleEnded(value, fitted: fitted)
                    }
            )
        }
    }

    // MARK: - Gesture handling

    private func handleChanged(_ value: DragGesture.Value, fitted: CGRect) {
        // Drag begin: hit-test existing text labels when the Text tool is
        // active, to distinguish move/edit from add. Rects are view-space.
        if dragStartLocation == nil {
            dragStartLocation = value.location
            if tool == .text {
                let rects = annotations.map { a -> CGRect in
                    a.tool == .text
                        ? TextAnnotationHitTest.bounds(text: a.text,
                                                       origin: toViewSpace(a.points.first ?? .zero, fitted: fitted),
                                                       fontSize: max(a.lineWidth * 4, 8))
                        : .null
                }
                movingTextIndex = TextAnnotationHitTest.topmostIndex(rects: rects, containing: value.location)
            }
        }

        // Moving (or potentially tapping) an existing text label.
        if let i = movingTextIndex {
            let start = dragStartLocation ?? value.location
            if hypot(value.location.x - start.x, value.location.y - start.y) > 4 { didMoveText = true }
            if didMoveText, i < annotations.count {
                annotations[i].points = [toBaseSpace(value.location, fitted: fitted)]
            }
            return
        }

        // Otherwise: pen/arrow/rectangle draw (text adds nothing here).
        guard tool != .text else { return }
        let p = toBaseSpace(value.location, fitted: fitted)
        switch tool {
        case .pen:
            if draft == nil {
                draft = Annotation(id: UUID(), tool: .pen, points: [p],
                                   text: "", colorHex: colorHex, lineWidth: lineWidth)
            } else {
                draft?.points.append(p)
            }
        case .arrow, .rectangle:
            let start = draft?.points.first ?? p
            draft = Annotation(id: UUID(), tool: tool, points: [start, p],
                               text: "", colorHex: colorHex, lineWidth: lineWidth)
        case .text:
            break
        }
    }

    private func handleEnded(_ value: DragGesture.Value, fitted: CGRect) {
        defer { movingTextIndex = nil; dragStartLocation = nil; didMoveText = false }

        if let i = movingTextIndex {
            // Moved: commit happened during onChanged. Tapped: re-edit.
            if !didMoveText, i < annotations.count { onEditText(i) }
            return
        }

        if tool == .text {
            onTextTap(toBaseSpace(value.location, fitted: fitted))
            return
        }
        if let draft {
            annotations.append(draft)
        }
        draft = nil
    }

    // MARK: - Coordinate mapping

    /// The rect the aspect-fit image actually occupies inside the view.
    private func fittedRect(in viewSize: CGSize) -> CGRect {
        let imgSize = base.size
        guard imgSize.width > 0, imgSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let scale = min(viewSize.width / imgSize.width, viewSize.height / imgSize.height)
        let w = imgSize.width * scale
        let h = imgSize.height * scale
        let x = (viewSize.width - w) / 2
        let y = (viewSize.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// View point -> base image pixel space.
    private func toBaseSpace(_ point: CGPoint, fitted: CGRect) -> CGPoint {
        guard fitted.width > 0, fitted.height > 0 else { return .zero }
        let relX = (point.x - fitted.minX) / fitted.width
        let relY = (point.y - fitted.minY) / fitted.height
        return CGPoint(x: relX * base.size.width, y: relY * base.size.height)
    }

    /// Base pixel space -> view point (for rendering the live overlay).
    private func toViewSpace(_ point: CGPoint, fitted: CGRect) -> CGPoint {
        guard base.size.width > 0, base.size.height > 0 else { return point }
        let x = fitted.minX + (point.x / base.size.width) * fitted.width
        let y = fitted.minY + (point.y / base.size.height) * fitted.height
        return CGPoint(x: x, y: y)
    }

    // MARK: - Overlay drawing (preview only; final render is ImageAnnotator)

    private func draw(_ ann: Annotation, in ctx: inout GraphicsContext, fitted: CGRect) {
        let color = Color(hex: ann.colorHex) ?? .red
        let viewPoints = ann.points.map { toViewSpace($0, fitted: fitted) }

        switch ann.tool {
        case .pen:
            guard viewPoints.count >= 2 else { return }
            var path = Path()
            path.move(to: viewPoints[0])
            for pt in viewPoints.dropFirst() { path.addLine(to: pt) }
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: ann.lineWidth, lineCap: .round, lineJoin: .round))

        case .arrow:
            guard viewPoints.count >= 2 else { return }
            let start = viewPoints[0], end = viewPoints[1]
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLen = max(ann.lineWidth * 3, 10)
            let headAngle = CGFloat.pi / 6
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x - headLen * cos(angle - headAngle),
                                     y: end.y - headLen * sin(angle - headAngle)))
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x - headLen * cos(angle + headAngle),
                                     y: end.y - headLen * sin(angle + headAngle)))
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: ann.lineWidth, lineCap: .round, lineJoin: .round))

        case .rectangle:
            guard viewPoints.count >= 2 else { return }
            let p0 = viewPoints[0], p1 = viewPoints[1]
            let rect = CGRect(x: min(p0.x, p1.x), y: min(p0.y, p1.y),
                              width: abs(p1.x - p0.x), height: abs(p1.y - p0.y))
            ctx.stroke(Path(rect), with: .color(color),
                       style: StrokeStyle(lineWidth: ann.lineWidth, lineJoin: .round))

        case .text:
            guard let origin = viewPoints.first, !ann.text.isEmpty else { return }
            let fontSize = max(ann.lineWidth * 4, 8)
            let resolved = ctx.resolve(Text(ann.text).font(.system(size: fontSize)).foregroundColor(color))
            ctx.draw(resolved, at: origin, anchor: .topLeading)
        }
    }
}

/// The annotation editor window content: toolbar + canvas + output actions.
struct ImageAnnotationView: View {
    let base: NSImage
    var onCopy: (Data) -> Void          // flattened PNG
    var onSaveToFolder: (Data) -> Void
    var onSaveToHistory: (Data) -> Void
    var onClose: () -> Void

    @State private var annotations: [Annotation] = []
    @State private var tool: AnnotationTool = .pen
    @State private var color: Color = Color(hex: "#FF3B30") ?? .red
    @State private var lineWidth: CGFloat = 4

    @State private var pendingTextPoint: CGPoint?
    @State private var pendingText: String = ""
    @State private var showingTextEntry = false
    @State private var editingTextIndex: Int?
    @State private var keyMonitor: Any?

    private var colorHex: String { color.toHex() ?? "#FF3B30" }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(8)
            Divider()
            AnnotationCanvas(
                base: base,
                annotations: $annotations,
                tool: tool,
                colorHex: colorHex,
                lineWidth: lineWidth,
                onTextTap: { point in
                    pendingTextPoint = point
                    editingTextIndex = nil
                    pendingText = ""
                    showingTextEntry = true
                },
                onEditText: { i in
                    editingTextIndex = i
                    pendingText = annotations[i].text
                    pendingTextPoint = nil
                    showingTextEntry = true
                }
            )
            .padding(8)
        }
        .frame(minWidth: 360, minHeight: 280)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .alert("Add Text", isPresented: $showingTextEntry) {
            TextField("Text", text: $pendingText)
            Button("Cancel", role: .cancel) { pendingTextPoint = nil; editingTextIndex = nil; pendingText = "" }
            Button("Add") { commitText() }
        }
    }

    /// The app is headless (no main menu) and the editor floats in a borderless
    /// panel, so SwiftUI `.keyboardShortcut` does not reliably resolve. Catch
    /// the editor's shortcuts with a local key monitor while it's on screen.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // While the text-entry alert is up, let the field handle keys.
            if showingTextEntry { return event }
            let mods = event.modifierFlags
            let cmd = mods.contains(.command)
            let shift = mods.contains(.shift)
            let key = event.charactersIgnoringModifiers?.lowercased()
            if event.keyCode == 53 { onClose(); return nil }            // Esc
            if cmd, !shift, key == "c" { flattenThenCallback(onCopy); return nil }
            if cmd, !shift, key == "s" { flattenThenCallback(onSaveToFolder); return nil }
            if cmd, shift, key == "s" { flattenThenCallback(onSaveToHistory); return nil }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $tool) {
                ForEach(AnnotationTool.allCases) { t in
                    Text(t.rawValue.capitalized).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .labelsHidden()

            ColorPicker("Color", selection: $color, supportsOpacity: false)
                .labelsHidden()

            Slider(value: $lineWidth, in: 1...20) { Text("Width") }
                .frame(width: 100)

            Button("Undo") {
                if !annotations.isEmpty { annotations.removeLast() }
            }
            .disabled(annotations.isEmpty)

            Spacer()

            Button("Copy") { flattenThenCallback(onCopy) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Save to Folder") { flattenThenCallback(onSaveToFolder) }
                .keyboardShortcut("s", modifiers: .command)
            Button("Save to History") { flattenThenCallback(onSaveToHistory) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }

    private func commitText() {
        if let i = editingTextIndex {
            if i < annotations.count {
                if pendingText.isEmpty { annotations.remove(at: i) }
                else { annotations[i].text = pendingText }
            }
            editingTextIndex = nil
            pendingText = ""
            pendingTextPoint = nil
            return
        }
        guard let point = pendingTextPoint, !pendingText.isEmpty else {
            pendingTextPoint = nil
            pendingText = ""
            return
        }
        annotations.append(Annotation(id: UUID(), tool: .text, points: [point],
                                      text: pendingText, colorHex: colorHex, lineWidth: lineWidth))
        pendingTextPoint = nil
        pendingText = ""
    }

    private func flattenThenCallback(_ callback: (Data) -> Void) {
        if let data = try? ImageAnnotator.flatten(base: base, annotations: annotations) {
            callback(data)
        }
        onClose()
    }
}

// MARK: - Color <-> hex helpers

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }

    func toHex() -> String? {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
