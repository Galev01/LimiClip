// ClipboardManager/Services/ScreenCapturer.swift
import AppKit
import CoreGraphics

/// Captures a full-screen bitmap for the iShot-style screen-freeze annotation
/// flow by shelling out to `/usr/sbin/screencapture`. (Direct CG/ScreenCaptureKit
/// grabs are either unavailable on recent macOS or async-only; the CLI is a
/// simple, well-supported one-shot that uses the Screen Recording permission
/// already granted to the app.)
enum ScreenCapturer {

    /// Silently captures the main display and returns the PNG bytes (top-left
    /// origin, native pixel resolution), or nil on failure (e.g. Screen
    /// Recording denied). Returns `Data` (Sendable) rather than `NSImage` so the
    /// caller can build the image on the main actor. Runs the capture off the
    /// main thread.
    static func captureMainDisplayPNG() async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("limiclip-freeze-\(UUID().uuidString).png")
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                // -x: silent (no sound/flash)  -m: main display only  -t png
                task.arguments = ["-x", "-m", "-t", "png", tmp.path]
                do {
                    try task.run()
                    task.waitUntilExit()
                } catch {
                    cont.resume(returning: nil)
                    return
                }
                let data = task.terminationStatus == 0 ? try? Data(contentsOf: tmp) : nil
                try? FileManager.default.removeItem(at: tmp)
                cont.resume(returning: data)
            }
        }
    }
}

/// Pure geometry mapping a selection rectangle in view points to the pixel
/// space of a `scale`×-denser capture. Kept separate so it can be unit-tested
/// without a display.
enum ScreenCaptureGeometry {
    /// View-point selection rect → pixel crop rect (both top-left origin).
    static func pixelRect(viewRect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: viewRect.minX * scale, y: viewRect.minY * scale,
               width: viewRect.width * scale, height: viewRect.height * scale)
    }

    /// An annotation point in view space → selection-relative pixel space, so a
    /// cropped (pixel-sized) base image and its annotations share one space.
    static func toSelectionPixels(_ point: CGPoint, selectionOrigin: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: (point.x - selectionOrigin.x) * scale,
                y: (point.y - selectionOrigin.y) * scale)
    }
}
