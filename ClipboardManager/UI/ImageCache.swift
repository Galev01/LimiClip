// ClipboardManager/UI/ImageCache.swift
import AppKit

/// Decoded-image cache keyed by a blob's immutable relative path.
///
/// The drawer re-evaluates card bodies frequently (on every clipboard change
/// and once per second via the live-refresh timer). Decoding the on-disk
/// thumbnail with `NSImage(contentsOf:)` inside `body` every time is the main
/// source of UI jank, so we decode each blob once and serve every subsequent
/// render from this cache.
final class ImageCache: @unchecked Sendable {

    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()

    init() {}

    /// Returns the decoded image for `key`, decoding from `url` on a miss.
    /// Returns nil if the file cannot be read.
    func image(forKey key: String, url: URL) -> NSImage? {
        let nsKey = key as NSString
        if let hit = cache.object(forKey: nsKey) { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: nsKey)
        return image
    }
}
