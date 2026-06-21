import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Extracts a small first-frame PNG thumbnail (plus pixel size + duration) from
/// a video file, using modern async AVFoundation (the synchronous
/// `copyCGImage(at:)` is deprecated on macOS 26). The PNG is capped to
/// `maxPixel` on its longest side via `ImageProcessor` so it's cheap to store
/// as an (encrypted) blob and to decode in the drawer. Returns nil if the file
/// can't be read as a video.
enum VideoThumbnail {

    /// First-frame PNG (≤`maxPixel` via `ImageProcessor`), the ORIGINAL video
    /// pixel size, and the duration in seconds. nil if unreadable.
    static func firstFrame(url: URL, maxPixel: CGFloat = 800) async -> (png: Data, size: CGSize, duration: Double)? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            // A tiny offset into the clip avoids an all-black first frame on
            // some encoders, while staying within very short recordings.
            let safeDuration = (durationSeconds.isFinite && durationSeconds > 0) ? durationSeconds : 0
            let target = CMTime(seconds: min(0.1, safeDuration), preferredTimescale: 600)

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .positiveInfinity

            let (cgImage, _) = try await generator.image(at: target)

            // Encode the raw CGImage to PNG, then run it through ImageProcessor
            // for the ≤maxPixel downsample + the original pixel-size readout.
            guard let pngData = encodePNG(cgImage) else { return nil }
            let processed = try ImageProcessor.process(data: pngData)
            return (png: processed.thumbnailData, size: processed.pixelSize, duration: safeDuration)
        } catch {
            Log.app.error("VideoThumbnail.firstFrame failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Encodes a CGImage to PNG `Data`. nil on failure.
    private static func encodePNG(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
