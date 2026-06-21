// ClipboardManager/Services/RecordingFolder.swift
import Foundation

/// Resolves and writes into the user-chosen folder for saved screen recordings.
/// The folder is persisted as a security-scoped bookmark in `Settings`.
/// Mirrors `AnnotationFolder` (security-scoped resolve, fallback).
enum RecordingFolder {

    /// The default folder used when no bookmark is set or it can't resolve:
    /// ~/Movies/LimiClip_Recordings (created on first save by `moveIntoFolder`).
    private static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("LimiClip_Recordings", isDirectory: true)
    }

    /// Resolves the saved security-scoped bookmark to a URL, or returns
    /// ~/Movies/LimiClip_Recordings when unset or stale/invalid.
    static func resolve(bookmark: Data?) -> URL {
        guard let bookmark else { return defaultFolder }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            return url
        } catch {
            return defaultFolder
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
        // Create the destination folder if it doesn't exist yet (e.g. the
        // default ~/Movies/LimiClip_Recordings on first save).
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "recording-\(timestamp).mov"
        let dest = folder.appendingPathComponent(name)
        try FileManager.default.moveItem(at: tempFile, to: dest)
        return dest
    }
}
