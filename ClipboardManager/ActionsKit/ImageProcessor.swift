// ClipboardManager/ActionsKit/ImageProcessor.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessor {

    static let maxThumbnailPixels: CGFloat = 800

    enum Failure: Error {
        case unreadable
        case noImage
        case encodeFailed
    }

    struct Result {
        let thumbnailData: Data
        let pixelSize: CGSize
    }

    /// Downsamples (if needed) and re-encodes the input image bytes to a
    /// PNG no larger than `maxThumbnailPixels` on its longest side. The
    /// `pixelSize` reports the ORIGINAL image's pixel dimensions so the UI
    /// can show "4032 × 3024" for a phone photo even though the on-disk
    /// thumbnail is smaller.
    static func process(data: Data) throws -> Result {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Failure.unreadable
        }

        // Read original dimensions from the file's metadata WITHOUT loading
        // the full bitmap. This is cheap.
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else {
            throw Failure.unreadable
        }
        let originalSize = CGSize(width: pixelWidth, height: pixelHeight)

        // Generate a thumbnail capped at maxThumbnailPixels. CGImageSource
        // does this efficiently using its own downsampling pipeline.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxThumbnailPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw Failure.noImage
        }

        // Encode thumbnail to PNG.
        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(outData, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encodeFailed
        }
        CGImageDestinationAddImage(dest, thumb, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw Failure.encodeFailed
        }

        return Result(thumbnailData: outData as Data, pixelSize: originalSize)
    }
}
