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

    enum Failure: Error, Equatable { case pathEscapesRoot(String) }

    /// Confines `relativePath` to `root`, throwing if it tries to escape (via
    /// `..`, an absolute path, or a symlink that resolves outside root). Shared
    /// by every path-taking method so the whole store is traversal-safe.
    private func resolve(relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !(relativePath as NSString).pathComponents.contains("..")
        else { throw Failure.pathEscapesRoot(relativePath) }

        let candidate = root.appendingPathComponent(relativePath, isDirectory: false)
        let basePath = root.resolvingSymlinksInPath().path
        let base = basePath.hasSuffix("/") ? basePath : basePath + "/"
        let resolved = candidate.resolvingSymlinksInPath().path
        guard resolved.hasPrefix(base) || resolved == String(base.dropLast()) else {
            throw Failure.pathEscapesRoot(relativePath)
        }
        return candidate
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

        let fullURL = try resolve(relativePath: relPath)
        try fm.createDirectory(at: fullURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = try cipher.map { try $0.seal(data) } ?? data
        try payload.write(to: fullURL, options: [.atomic])
        return relPath
    }

    func read(relativePath: String) throws -> Data {
        let fullURL = try resolve(relativePath: relativePath)
        let raw = try Data(contentsOf: fullURL)
        // Use the throwing open so an undecryptable sealed blob (e.g. a
        // key-mismatch from a re-signed/stale binary) surfaces as an error
        // rather than silently returning empty Data that the UI renders as a
        // blank/gray placeholder.
        return try cipher.map { try $0.open(sealedBlob: raw) } ?? raw
    }

    func delete(relativePath: String) throws {
        let fullURL = try resolve(relativePath: relativePath)
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
    /// Throws if the path tries to escape `root`.
    func absoluteURL(forRelativePath relativePath: String) throws -> URL {
        try resolve(relativePath: relativePath)
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
