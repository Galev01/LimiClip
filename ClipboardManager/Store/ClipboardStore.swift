// ClipboardManager/Store/ClipboardStore.swift
import Foundation
import GRDB
import CryptoKit
import CoreGraphics

/// Thread-safe SQLite-backed store for clipboard history.
///
/// Backed by GRDB. The encryption key lives in the user's Keychain (see
/// `DatabaseKey`) — the actual SQLCipher integration is a follow-up; for
/// Phase 2 the production database is plain SQLite. The store is `Sendable`
/// because it wraps a `DatabaseQueue` which serialises all access.
final class ClipboardStore: @unchecked Sendable {

    private let queue: any DatabaseWriter

    // MARK: - Initialisation

    /// Production init: opens (and migrates) the database file in
    /// Application Support.
    convenience init() throws {
        // Note: SQLCipher passphrase wiring is deferred — this opens a
        // standard SQLite file. The DatabaseKey machinery still runs so the
        // key exists by the time we add encryption.
        _ = try DatabaseKey.loadOrCreate()
        let url = try Self.databaseURL()
        let queue = try DatabaseQueue(path: url.path)
        try self.init(queue: queue)
    }

    /// Init from a prepared configuration (used by tests with an in-memory DB).
    convenience init(configuration: Configuration) throws {
        let queue = try DatabaseQueue(configuration: configuration)
        try self.init(queue: queue)
    }

    private init(queue: any DatabaseWriter) throws {
        self.queue = queue
        var migrator = DatabaseMigrator()
        Migrations.register(&migrator)
        try migrator.migrate(queue)
    }

    /// Application Support / Clipboard Manager / clipboard.sqlite
    private static func databaseURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("Clipboard Manager", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clipboard.sqlite", isDirectory: false)
    }

    // MARK: - Test helpers

    /// In-memory configuration. For unit tests only.
    static func testingConfiguration() -> Configuration {
        Configuration()
    }

    func testingInsertStaleItem(body: String, createdAt: Int64) throws {
        try queue.write { db in
            var item = Item(
                id: nil,
                kind: "text",
                subtype: "plain",
                contentHash: Self.hash(body),
                body: body,
                blobPath: nil,
                dimensions: nil,
                byteSize: body.utf8.count,
                sourceApp: nil,
                sourceBundleId: nil,
                createdAt: createdAt,
                pinned: false,
                snippetId: nil,
                deletedAt: nil
            )
            try item.insert(db)
        }
    }

    // MARK: - Insertion

    /// Records a text clipboard item. Returns the stored Item, or nil if the
    /// content was empty, the source app is excluded, or the body was already
    /// recorded (in which case the existing row's createdAt is bumped).
    @discardableResult
    func recordText(_ raw: String, sourceApp: String?, sourceBundleId: String?) throws -> Item? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let bundleId = sourceBundleId, try isExcluded(bundleId: bundleId) {
            Log.app.info("skipping copy from excluded bundle: \(bundleId, privacy: .public)")
            return nil
        }

        let subtype = SubtypeDetector.detect(raw)
        let kindVal: ItemKind = .text(subtype)
        let hash = Self.hash(raw)
        let now = Int64(Date().timeIntervalSince1970)

        let result: Item = try queue.write { db in
            // Dedupe by hash among non-deleted rows.
            if var existing = try Item
                .filter(Item.Columns.contentHash == hash && Item.Columns.deletedAt == nil)
                .fetchOne(db)
            {
                existing.createdAt = now
                try existing.update(db)
                return existing
            }
            var item = Item(
                id: nil,
                kind: kindVal.kindColumn,
                subtype: kindVal.subtypeColumn,
                contentHash: hash,
                body: raw,
                blobPath: nil,
                dimensions: nil,
                byteSize: raw.utf8.count,
                sourceApp: sourceApp,
                sourceBundleId: sourceBundleId,
                createdAt: now,
                pinned: false,
                snippetId: nil,
                deletedAt: nil
            )
            try item.insert(db)
            return item
        }
        postChange()
        return result
    }

    /// Records an image clipboard item. `contentHash` is the SHA256 of the
    /// ORIGINAL image bytes (computed by the caller — the monitor — so we
    /// don't double-hash). On dedupe hit, the existing row's createdAt is
    /// bumped and the new blob path is NOT replaced (caller should delete
    /// the unused new blob).
    @discardableResult
    func recordImage(
        contentHash: String,
        blobPath: String,
        dimensions: CGSize,
        byteSize: Int,
        sourceApp: String?,
        sourceBundleId: String?
    ) throws -> Item? {
        if let bundleId = sourceBundleId, try isExcluded(bundleId: bundleId) {
            Log.app.info("skipping image from excluded bundle: \(bundleId, privacy: .public)")
            return nil
        }
        let now = Int64(Date().timeIntervalSince1970)
        let dimsString = "\(Int(dimensions.width))x\(Int(dimensions.height))"

        let result: Item = try queue.write { db in
            if var existing = try Item
                .filter(Item.Columns.contentHash == contentHash && Item.Columns.deletedAt == nil)
                .fetchOne(db)
            {
                existing.createdAt = now
                try existing.update(db)
                return existing
            }
            var item = Item(
                id: nil,
                kind: "image",
                subtype: nil,
                contentHash: contentHash,
                body: blobPath,
                blobPath: blobPath,
                dimensions: dimsString,
                byteSize: byteSize,
                sourceApp: sourceApp,
                sourceBundleId: sourceBundleId,
                createdAt: now,
                pinned: false,
                snippetId: nil,
                deletedAt: nil
            )
            try item.insert(db)
            return item
        }
        postChange()
        return result
    }

    /// Records a file clipboard item from a `FileReference`. Dedupe is by
    /// path (so re-copying the same file is a no-op).
    @discardableResult
    func recordFile(
        reference: FileReference,
        sourceApp: String?,
        sourceBundleId: String?
    ) throws -> Item? {
        if let bundleId = sourceBundleId, try isExcluded(bundleId: bundleId) {
            Log.app.info("skipping file from excluded bundle: \(bundleId, privacy: .public)")
            return nil
        }
        let now = Int64(Date().timeIntervalSince1970)
        let body = try reference.encodedJSON()
        let hash = Self.hash(reference.path)

        let result: Item = try queue.write { db in
            if var existing = try Item
                .filter(Item.Columns.contentHash == hash && Item.Columns.deletedAt == nil)
                .fetchOne(db)
            {
                existing.createdAt = now
                try existing.update(db)
                return existing
            }
            var item = Item(
                id: nil,
                kind: "file",
                subtype: nil,
                contentHash: hash,
                body: body,
                blobPath: nil,
                dimensions: nil,
                byteSize: Int(reference.byteSize),
                sourceApp: sourceApp,
                sourceBundleId: sourceBundleId,
                createdAt: now,
                pinned: false,
                snippetId: nil,
                deletedAt: nil
            )
            try item.insert(db)
            return item
        }
        postChange()
        return result
    }

    // MARK: - Queries

    func countItems(includingDeleted: Bool = false) throws -> Int {
        try queue.read { db in
            var query = Item.all()
            if !includingDeleted { query = query.filter(Item.Columns.deletedAt == nil) }
            return try query.fetchCount(db)
        }
    }

    /// Most-recent first, deleted items excluded. Caller specifies a hard cap.
    func recentItems(limit: Int) throws -> [Item] {
        try queue.read { db in
            try Item
                .filter(Item.Columns.deletedAt == nil)
                .order(Item.Columns.createdAt.desc, Item.Columns.id.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Soft delete

    func softDelete(itemId: Int64) throws {
        let now = Int64(Date().timeIntervalSince1970)
        _ = try queue.write { db in
            try Item.filter(Item.Columns.id == itemId)
                .updateAll(db, [Item.Columns.deletedAt.set(to: now)])
        }
        postChange()
    }

    /// Hard-deletes all non-pinned, non-soft-deleted items. Pinned items are preserved.
    func clearAll() throws {
        _ = try queue.write { db in
            try Item.filter(Item.Columns.pinned == false && Item.Columns.deletedAt == nil)
                .deleteAll(db)
        }
        postChange()
    }

    func setPinned(itemId: Int64, pinned: Bool) throws {
        _ = try queue.write { db in
            try Item.filter(Item.Columns.id == itemId)
                .updateAll(db, [Item.Columns.pinned.set(to: pinned)])
        }
        postChange()
    }

    // MARK: - Retention

    /// Hard-delete items whose createdAt is older than `days` days, and any
    /// item soft-deleted more than 24h ago. Pinned items are never purged.
    func purgeOlderThan(days: Int) throws {
        let cutoff = Int64(Date().timeIntervalSince1970) - Int64(days) * 86_400
        let undeleteCutoff = Int64(Date().timeIntervalSince1970) - 86_400
        _ = try queue.write { db in
            try Item.filter(Item.Columns.createdAt < cutoff && Item.Columns.pinned == false)
                .deleteAll(db)
            // SQL: `WHERE deletedAt < X` is NULL-safe — NULL comparisons return false,
            // so non-soft-deleted rows are untouched without needing an extra null check.
            try Item.filter(Item.Columns.deletedAt < undeleteCutoff)
                .deleteAll(db)
        }
        postChange()
    }

    /// Keep at most `max` non-pinned items, ordered by createdAt desc. Older
    /// non-pinned items are hard-deleted.
    func purgeBeyondCount(max: Int) throws {
        _ = try queue.write { db in
            let keepIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM items
                WHERE deletedAt IS NULL AND pinned = 0
                ORDER BY createdAt DESC, id DESC
                LIMIT \(max)
                """)
            if keepIds.isEmpty {
                try Item.filter(Item.Columns.pinned == false).deleteAll(db)
            } else {
                try Item.filter(!keepIds.contains(Item.Columns.id) && Item.Columns.pinned == false)
                    .deleteAll(db)
            }
        }
        postChange()
    }

    // MARK: - Exclusions

    func seedDefaultExclusionsIfNeeded() throws {
        try queue.write { db in
            for exclusion in DefaultExclusions.list {
                if try Exclusion.fetchOne(db, key: exclusion.bundleId) == nil {
                    try exclusion.insert(db)
                }
            }
        }
    }

    func addExclusion(bundleId: String, name: String) throws {
        try queue.write { db in
            var e = Exclusion(bundleId: bundleId, name: name)
            try e.save(db)
        }
        postChange()
    }

    func removeExclusion(bundleId: String) throws {
        _ = try queue.write { db in
            try Exclusion.deleteOne(db, key: bundleId)
        }
        postChange()
    }

    func allExclusions() throws -> [Exclusion] {
        try queue.read { db in
            try Exclusion.order(Exclusion.Columns.name.asc).fetchAll(db)
        }
    }

    func isExcluded(bundleId: String) throws -> Bool {
        try queue.read { db in
            try Exclusion.fetchOne(db, key: bundleId) != nil
        }
    }

    // MARK: - Hashing

    private static func hash(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Change notifications

    private func postChange() {
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
    }
}

extension Notification.Name {
    /// Posted after any successful insert / delete / purge in ClipboardStore.
    /// Subscribers should re-query whatever slice they care about.
    static let clipboardStoreDidChange = Notification.Name("ClipboardStoreDidChange")
}
