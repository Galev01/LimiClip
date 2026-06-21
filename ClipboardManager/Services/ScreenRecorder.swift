// ClipboardManager/Services/ScreenRecorder.swift
import AppKit
import Foundation

/// Records the screen by shelling out to `/usr/sbin/screencapture` in video mode.
/// Like `ScreenCapturer`, this uses the Screen Recording permission already
/// granted to the app and avoids the async-only / availability constraints of
/// ScreenCaptureKit. The process runs until interrupted (SIGINT), at which point
/// `screencapture` finalizes the `.mov`.
///
/// EMPIRICALLY VERIFIED FLAGS (2026-06-21, macOS 26 / Darwin 25.5.0):
///   screencapture -v -V1 -R0,0,200,200 /tmp/limiclip-rectest.mov
/// produced a valid, non-empty (17 KB) QuickTime movie whose video track
/// `avmediainfo` reported as "Duration: 0.995 seconds (597/600)". So `-v` +
/// `-R<x,y,w,h>` DOES record a region to video. (`mdls kMDItemDurationSeconds`
/// returns null for such short clips — a Spotlight importer quirk, not a
/// recording failure; `avmediainfo` confirms the real track duration.)
///   - `-v`  : record video
///   - `-g`  : also capture audio (microphone) — added only when `audio` is true
///   - `-R x,y,w,h` : capture the global (top-left origin) rectangle
/// `-V1` (1-second duration limit) is only used for the empirical/integration
/// check; the real flow records until `stop()` interrupts the process.
@MainActor final class ScreenRecorder {
    private var task: Process?

    var isRecording: Bool { task != nil }

    /// Launches `screencapture` video recording of `globalRect` to `outputURL`.
    /// Returns false if launch fails. `onFinish` is called on the main actor
    /// with the output URL once the process exits (file finalized), or nil on
    /// failure (non-zero exit or missing output file). The recorder also clears
    /// its `task` here, so `isRecording` returns to false whether the process
    /// was stopped via `stop()` or exited on its own (death, duration limit).
    @discardableResult
    func start(globalRect: CGRect,
               audio: Bool,
               outputURL: URL,
               onFinish: @escaping @MainActor (URL?) -> Void) -> Bool {
        guard task == nil else { return false }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = Self.arguments(globalRect: globalRect,
                                        audio: audio,
                                        outputPath: outputURL.path)
        // terminationHandler is a non-isolated @Sendable closure, so it cannot
        // call the @MainActor `onFinish` (or touch `task`) directly. Hop to the
        // main thread, then `MainActor.assumeIsolated` to re-enter main-actor
        // isolation — the same pattern used in ScreenshotImporter. (Capturing
        // the @MainActor `onFinish` here is legal: global-actor closures are
        // implicitly Sendable.)
        proc.terminationHandler = { finished in
            let ok = finished.terminationStatus == 0
                && FileManager.default.fileExists(atPath: outputURL.path)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.task = nil
                    onFinish(ok ? outputURL : nil)
                }
            }
        }

        do {
            try proc.run()
        } catch {
            return false
        }
        task = proc
        return true
    }

    /// Interrupts the recording process (SIGINT → screencapture finalizes the
    /// `.mov`); finalization fires `terminationHandler`, which clears `task` and
    /// calls the `onFinish` passed to `start`.
    func stop() {
        task?.interrupt()
    }

    /// PURE, nonisolated: the `screencapture` argument vector for video recording.
    /// See the file-header comment for the empirically-verified flag set.
    nonisolated static func arguments(globalRect: CGRect,
                                      audio: Bool,
                                      outputPath: String) -> [String] {
        let region = "-R\(Int(globalRect.minX.rounded())),\(Int(globalRect.minY.rounded())),\(Int(globalRect.width.rounded())),\(Int(globalRect.height.rounded()))"
        return ["-v"] + (audio ? ["-g"] : []) + [region, outputPath]
    }
}
