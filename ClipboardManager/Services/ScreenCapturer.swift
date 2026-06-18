// ClipboardManager/Services/ScreenCapturer.swift
import AppKit
import CoreGraphics

/// Captures a full-screen bitmap for the iShot-style screen-freeze annotation
/// flow by shelling out to `/usr/sbin/screencapture`. (Direct CG/ScreenCaptureKit
/// grabs are either unavailable on recent macOS or async-only; the CLI is a
/// simple, well-supported one-shot that uses the Screen Recording permission
/// already granted to the app.)
enum ScreenCapturer {

    /// Silently captures the screen rectangle `globalRect` (screencapture's
    /// top-left global coordinate space, points) and returns the PNG bytes at
    /// native pixel resolution, or nil on failure. Capturing by region (`-R`)
    /// rather than by display index means the correct monitor is captured even
    /// in multi-display setups. Returns `Data` (Sendable); runs off the main
    /// thread.
    static func captureRegionPNG(globalRect r: CGRect) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("limiclip-freeze-\(UUID().uuidString).png")
                let region = "-R\(Int(r.minX.rounded())),\(Int(r.minY.rounded())),\(Int(r.width.rounded())),\(Int(r.height.rounded()))"
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                task.arguments = ["-x", region, "-t", "png", tmp.path]   // -x: silent
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

    /// Converts an `NSScreen.frame` (AppKit global, bottom-left origin) to the
    /// top-left global rect `screencapture -R` expects, given the primary
    /// display's height. This is what makes capture target the SAME monitor the
    /// overlay is shown on, regardless of which display is primary.
    static func screencaptureRect(for screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX,
               y: primaryHeight - screenFrame.maxY,
               width: screenFrame.width,
               height: screenFrame.height)
    }
}
