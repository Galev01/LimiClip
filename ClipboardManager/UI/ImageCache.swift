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

    /// Returns the decoded image for `key`, reading + decrypting the blob via
    /// `blobStore` on a miss. Returns nil if the blob cannot be read/decoded.
    /// Decryption happens at most once per key — every later render is a cache
    /// hit, so encrypting blobs does not add per-render cost.
    func image(forKey key: String, blobStore: BlobStore, path: String) -> NSImage? {
        let nsKey = key as NSString
        if let hit = cache.object(forKey: nsKey) { return hit }
        guard let data = try? blobStore.read(relativePath: path),
              let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: nsKey)
        return image
    }
}
