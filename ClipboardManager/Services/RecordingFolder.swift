// ClipboardManager/Services/RecordingFolder.swift
import Foundation

/// Resolves and writes into the user-chosen folder for saved screen recordings.
/// The folder is persisted as a security-scoped bookmark in `Settings`.
/// Mirrors `AnnotationFolder` (security-scoped resolve, fallback).
enum RecordingFolder {

    /// The ~/Movies fallback used when no bookmark is set or it can't resolve.
    private static var moviesFallback: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
    }

    /// Resolves the saved security-scoped bookmark to a URL, or returns
    /// ~/Movies when unset or stale/invalid.
    static func resolve(bookmark: Data?) -> URL {
        guard let bookmark else { return moviesFallback }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            return url
        } catch {
            return moviesFallback
        }
    }

    /// Creates a security-scoped bookmark for the given folder URL.
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope,
                             includingResourceValuesForKeys: nil,
                             relativeTo: nil)
    }

    /// Moves `tempFile` into `folder` as `recording-<timestamp>.mov`; returns the
    /// final URL. Caller wraps with `startAccessingSecurityScopedResource()` when
    /// using a resolved bookmark.
    static func moveIntoFolder(_ tempFile: URL, folder: URL, timestamp: Int64) throws -> URL {
        let name = "recording-\(timestamp).mov"
        let dest = folder.appendingPathComponent(name)
        try FileManager.default.moveItem(at: tempFile, to: dest)
        return dest
    }
}
