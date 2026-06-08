// ClipboardManager/UI/ImageCache.swift
import AppKit

/// Decoded-image cache keyed by a blob's immutable relative path.
///
/// `NSCache` is internally thread-safe (its accessors are documented as safe to
/// call from any thread without external locking), which is why `@unchecked
/// Sendable` is sound here. We cap the entry count so decoded thumbnails can
/// never grow without bound, independent of the on-disk image cap.
final class ImageCache: @unchecked Sendable {

    static let shared = ImageCache()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 256   // far above the UI's visibleLimit; bounds worst case
        return c
    }()

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
