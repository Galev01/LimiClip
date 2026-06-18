// ClipboardManager/Services/AnnotationFolder.swift
import Foundation

/// Resolves and writes into the user-chosen folder for saved annotated images.
/// The folder is persisted as a security-scoped bookmark in `Settings`.
enum AnnotationFolder {

    /// The ~/Pictures fallback used when no bookmark is set or it can't resolve.
    private static var picturesFallback: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
    }

    /// Resolves the saved security-scoped bookmark to a URL, or returns
    /// ~/Pictures when unset or stale/invalid.
    static func resolve(bookmark: Data?) -> URL {
        guard let bookmark else { return picturesFallback }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            return url
        } catch {
            return picturesFallback
        }
    }

    /// Creates a security-scoped bookmark for the given folder URL.
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope,
                             includingResourceValuesForKeys: nil,
                             relativeTo: nil)
    }

    /// Writes `png` as `annotated-<timestamp>.png` into `folder`; returns the URL.
    /// Caller wraps with `startAccessingSecurityScopedResource()` when using a
    /// resolved bookmark.
    static func write(png: Data, to folder: URL, timestamp: Int64) throws -> URL {
        let name = "annotated-\(timestamp).png"
        let dest = folder.appendingPathComponent(name)
        try png.write(to: dest)
        return dest
    }
}
