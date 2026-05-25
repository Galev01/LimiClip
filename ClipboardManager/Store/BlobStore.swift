// ClipboardManager/Store/BlobStore.swift
import Foundation

/// On-disk binary storage for images (and, later, any binary blob too large
/// to live in the SQLite row). Files are sharded two levels deep by leading
/// hex chars of the UUID-derived filename, so any single directory stays
/// small even with tens of thousands of items:
///
///     <root>/<aa>/<bb>/<uuid>.<ext>
final class BlobStore: @unchecked Sendable {

    private let root: URL
    private let fm: FileManager

    /// Production initializer — uses Application Support / Clipboard Manager / blobs.
    convenience init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = appSupport.appendingPathComponent("Clipboard Manager", isDirectory: true)
                            .appendingPathComponent("blobs", isDirectory: true)
        try self.init(rootDirectory: dir)
    }

    init(rootDirectory: URL, fileManager: FileManager = .default) throws {
        self.root = rootDirectory
        self.fm = fileManager
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    /// Writes data to a freshly-generated sharded path. Returns the relative
    /// path under `root` (e.g. "ab/cd/uuid.png").
    @discardableResult
    func write(data: Data, fileExtension: String) throws -> String {
        let uuid = UUID().uuidString.lowercased()
        let aa = String(uuid.prefix(2))
        let bb = String(uuid.dropFirst(2).prefix(2))
        let relDir = "\(aa)/\(bb)"
        let filename = "\(uuid).\(fileExtension)"
        let relPath = "\(relDir)/\(filename)"

        let fullDir = root.appendingPathComponent(relDir, isDirectory: true)
        try fm.createDirectory(at: fullDir, withIntermediateDirectories: true)
        let fullURL = fullDir.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: fullURL, options: [.atomic])
        return relPath
    }

    func read(relativePath: String) throws -> Data {
        let fullURL = root.appendingPathComponent(relativePath, isDirectory: false)
        return try Data(contentsOf: fullURL)
    }

    func delete(relativePath: String) throws {
        let fullURL = root.appendingPathComponent(relativePath, isDirectory: false)
        try fm.removeItem(at: fullURL)
    }

    /// Absolute file URL — used by SwiftUI's `Image(nsImage:)` via `NSImage(contentsOfFile:)`.
    func absoluteURL(forRelativePath relativePath: String) -> URL {
        root.appendingPathComponent(relativePath, isDirectory: false)
    }
}

// MARK: - SwiftUI environment

import SwiftUI

private struct BlobStoreKey: EnvironmentKey {
    static let defaultValue: BlobStore? = nil
}

extension EnvironmentValues {
    var blobStore: BlobStore? {
        get { self[BlobStoreKey.self] }
        set { self[BlobStoreKey.self] = newValue }
    }
}
