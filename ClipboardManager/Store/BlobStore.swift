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
    private let cipher: FieldCipher?

    /// Production initializer — uses Application Support / Clipboard Manager / blobs.
    convenience init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = appSupport.appendingPathComponent("Clipboard Manager", isDirectory: true)
                            .appendingPathComponent("blobs", isDirectory: true)
        let cipher = FieldCipher(masterKeyData: try DatabaseKey.loadOrCreate())
        try self.init(rootDirectory: dir, cipher: cipher)
    }

    init(rootDirectory: URL, fileManager: FileManager = .default, cipher: FieldCipher? = nil) throws {
        self.root = rootDirectory
        self.fm = fileManager
        self.cipher = cipher
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
        let payload = try cipher.map { try $0.seal(data) } ?? data
        try payload.write(to: fullURL, options: [.atomic])
        return relPath
    }

    func read(relativePath: String) throws -> Data {
        let fullURL = root.appendingPathComponent(relativePath, isDirectory: false)
        let raw = try Data(contentsOf: fullURL)
        return cipher.map { $0.open(raw) } ?? raw
    }

    func delete(relativePath: String) throws {
        let fullURL = root.appendingPathComponent(relativePath, isDirectory: false)
        try fm.removeItem(at: fullURL)
    }

    /// Deletes every on-disk blob whose relative path is NOT in `referenced`,
    /// returning the relative paths removed. Best-effort: a file that fails to
    /// delete is skipped rather than aborting the whole sweep.
    @discardableResult
    func purgeOrphans(referenced: Set<String>) throws -> [String] {
        // Resolve symlinks on both sides: enumerator URLs can come back
        // symlink-resolved (e.g. /var -> /private/var on macOS) while `root`
        // is not, which would break a naive prefix comparison.
        let basePath = root.resolvingSymlinksInPath().path
        let base = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var removed: [String] = []
        for case let url as URL in enumerator {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isFile else { continue }
            let filePath = url.resolvingSymlinksInPath().path
            guard filePath.hasPrefix(base) else { continue }
            let relativePath = String(filePath.dropFirst(base.count))
            if referenced.contains(relativePath) { continue }
            // Best-effort: skip files we can't delete rather than aborting.
            if (try? fm.removeItem(at: url)) != nil {
                removed.append(relativePath)
            }
        }
        return removed
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
