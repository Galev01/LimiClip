// ClipboardManager/Store/ClipboardStore.swift
import Foundation
import GRDB
import CryptoKit
import CoreGraphics

/// Thread-safe SQLite-backed store for clipboard history.
///
/// Backed by GRDB. Sensitive columns (`body`, `sourceApp`, `sourceBundleId`)
/// are encrypted at the application layer with AES-256-GCM via `FieldCipher`,
/// using the key in the user's Keychain (`DatabaseKey`); the dedup `contentHash`
/// is a keyed HMAC. So clipboard contents are ciphertext at rest even though the
/// SQLite file itself is standard SQLite (`secure_delete` zeroes freed pages).
/// The store is `Sendable` because it wraps a `DatabaseQueue` which serialises
/// all access.
final class ClipboardStore: @unchecked Sendable {

    private let queue: any DatabaseWriter
    private let cipher: FieldCipher
    private let blobStore: BlobStore?

    /// Hard caps enforced on write, independent of the user's history-size
    /// setting. Pins are exempt from retention purges, so they're bounded
    /// here; photos are bounded so the drawer never has to decode more than a
    /// handful of image thumbnails.
    static let maxPinnedItems = 15
    static let maxImages = 5

    /// Guard against pathological inputs only (decode cost / memory), NOT a
    /// disk bound: pasteboard images usually arrive as UNCOMPRESSED TIFF, so a
    /// modest Retina screenshot is 15-60 MB of raw bytes. Disk use is already
    /// bounded by the ≤800px thumbnail (`ImageProcessor.maxThumbnailPixels`)
    /// plus `maxImages` eviction — capping raw bytes at 10 MB silently dropped
    /// nearly every native-app image copy.
    static let maxImageBytes = 100 * 1024 * 1024   // 100 MB

    /// Upper bound on a single captured text item, measured in UTF-8 bytes.
    /// Oversized pastes are dropped (not truncated) to avoid the memory/disk
    /// cost of hashing + encrypting + storing a multi-MB string, and because
    /// truncation would silently corrupt the user's content.
    static let maxTextBytes = 2 * 1024 * 1024

    // MARK: - Initialisation

    /// Production init: opens (and migrates) the database file in
    /// Application Support. Sensitive columns are encrypted at the application
    /// layer with the key in `DatabaseKey` (see `FieldCipher`); the SQLite file
    /// itself is standard SQLite, with `secure_delete` on so freed pages are
    /// zeroed.
    convenience init() throws {
        let cipher = FieldCipher(masterKeyData: try DatabaseKey.loadOrCreate())
        let url = try Self.databaseURL()
        try self.init(path: url.path, cipher: cipher)
    }

    /// Production init wiring the blob store so a single-item delete can eagerly
    /// remove the backing blob file (instead of waiting for GC/retention).
    convenience init(blobStore: BlobStore) throws {
        let cipher = FieldCipher(masterKeyData: try DatabaseKey.loadOrCreate())
        let url = try Self.databaseURL()
        try self.init(path: url.path, cipher: cipher, blobStore: blobStore)
    }

    /// Opens (and migrates) the database file at `path` with the given cipher.
    convenience init(path: String, cipher: FieldCipher, blobStore: BlobStore? = nil) throws {
        let queue = try DatabaseQueue(path: path, configuration: Self.makeConfiguration())
        try self.init(queue: queue, cipher: cipher, blobStore: blobStore)
    }

    /// Init from a prepared configuration (used by tests with an in-memory DB).
    convenience init(
        configuration: Configuration,
        cipher: FieldCipher = FieldCipher(masterKeyData: Data(repeating: 7, count: 32)),
        blobStore: BlobStore? = nil
    ) throws {
        let queue = try DatabaseQueue(configuration: configuration)
        try self.init(queue: queue, cipher: cipher, blobStore: blobStore)
    }

    private init(queue: any DatabaseWriter, cipher: FieldCipher, blobStore: BlobStore? = nil) throws {
        self.queue = queue
        self.cipher = cipher
        self.blobStore = blobStore
        var migrator = DatabaseMigrator()
        Migrations.register(&migrator)
        try migrator.migrate(queue)
        try migrateUnencryptedRows()
    }

    /// Shared DB configuration. `secure_delete` zeroes freed pages so deleted
    /// rows (e.g. after Clear All) can't be recovered from the freelist.
    static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        return config
    }

    /// One-time, idempotent migration of legacy plaintext rows (written before
    /// encryption shipped) to encrypted form. A row whose `body` is already
    /// sealed is skipped, so this is cheap on every launch and safe to re-run.
    /// Text/file rows also get their dedup hash re-keyed (HMAC); image rows keep
    /// their high-entropy SHA256. Runs `VACUUM` only if anything changed, to
    /// purge the now-stale plaintext from the freelist.
    private func migrateUnencryptedRows() throws {
        let migrated = try queue.write { db -> Int in
            var count = 0
            let rows = try Row.fetchAll(db, sql: "SELECT id, kind, body, sourceApp, sourceBundleId FROM items")
            for row in rows {
                let body: String = row["body"]
                if cipher.isSealed(body) { continue }

                let id: Int64 = row["id"]
                let kind: String = row["kind"]
                let app: String? = row["sourceApp"]
                let bundle: String? = row["sourceBundleId"]

                let sealedBody = try cipher.seal(body)
                let sealedApp = try app.map { try cipher.seal($0) }
                let sealedBundle = try bundle.map { try cipher.seal($0) }

                switch kind {
                case "text":
                    try db.execute(
                        sql: "UPDATE items SET body = ?, sourceApp = ?, sourceBundleId = ?, contentHash = ? WHERE id = ?",
                        arguments: [sealedBody, sealedApp, sealedBundle, cipher.dedupHash(body), id])
                case "file":
                    let decodedPath = (try? FileReference.decodingJSON(body))?.path
                    if decodedPath == nil { Log.app.info("file row \(id, privacy: .public): JSON parse failed, using body as path") }
                    let path = decodedPath ?? body
                    try db.execute(
                        sql: "UPDATE items SET body = ?, sourceApp = ?, sourceBundleId = ?, contentHash = ? WHERE id = ?",
                        arguments: [sealedBody, sealedApp, sealedBundle, cipher.dedupHash(path), id])
                default:
                    // image (and anything else): keep the existing content hash.
                    try db.execute(
                        sql: "UPDATE items SET body = ?, sourceApp = ?, sourceBundleId = ? WHERE id = ?",
                        arguments: [sealedBody, sealedApp, sealedBundle, id])
                }
                count += 1
            }
            return count
        }
        if migrated > 0 {
            try queue.writeWithoutTransaction { db in try db.execute(sql: "VACUUM") }
        }
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
        makeConfiguration()
    }

    func testingInsertStaleItem(body: String, createdAt: Int64) throws {
        let hash = cipher.dedupHash(body)
        let sealedBody = try cipher.seal(body)
        try queue.write { db in
            var item = Item(
                id: nil,
                kind: "text",
                subtype: "plain",
                contentHash: hash,
                body: sealedBody,
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
        if raw.utf8.count > Self.maxTextBytes {
            Log.app.info("dropping oversized clipboard text: \(raw.utf8.count, privacy: .public) bytes > cap \(Self.maxTextBytes, privacy: .public)")
            return nil
        }
        if let bundleId = sourceBundleId, try isExcluded(bundleId: bundleId) {
            Log.app.info("skipping copy from excluded bundle: \(bundleId, privacy: .public)")
            return nil
        }

        let subtype = SubtypeDetector.detect(raw)
        let kindVal: ItemKind = .text(subtype)
        let hash = cipher.dedupHash(raw)
        let sealedBody = try cipher.seal(raw)
        let sealedApp = try sealOptional(sourceApp)
        let sealedBundle = try sealOptional(sourceBundleId)
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
                body: sealedBody,
                blobPath: nil,
                dimensions: nil,
                byteSize: raw.utf8.count,
                sourceApp: sealedApp,
                sourceBundleId: sealedBundle,
                createdAt: now,
                pinned: false,
                snippetId: nil,
                deletedAt: nil
            )
            try item.insert(db)
            return item
        }
        postChange()
        return decrypt(result)
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
        guard byteSize <= Self.maxImageBytes else {
            Log.app.info("dropping oversize image (\(byteSize, privacy: .public) bytes)")
            return nil
        }
        if let bundleId = sourceBundleId, try isExcluded(bundleId: bundleId) {
            Log.app.info("skipping image from excluded bundle: \(bundleId, privacy: .public)")
            return nil
        }
        let now = Int64(Date().timeIntervalSince1970)
        let dimsString = "\(Int(dimensions.width))x\(Int(dimensions.height))"
        // contentHash stays the caller's SHA256 of the original (high-entropy)
        // image bytes — not brute-forceable, so no keyed hash needed. The
        // blobPath column stays plaintext (blob GC matches it against disk);
        // only the blob file's bytes are encrypted, by BlobStore.
        let sealedBody = try cipher.seal(blobPath)
        let sealedApp = try sealOptional(sourceApp)
        let sealedBundle = try sealOptional(sourceBundleId)

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
                body: sealedBody,
                blobPath: blobPath,
                dimensions: dimsString,
                byteSize: byteSize,
                sourceApp: sealedApp,
                sourceBundleId: sealedBundle,
                createdAt: now,
                pinned: false,
                snippetId: nil,
                deletedAt: nil
            )
            try item.insert(db)
            try Self.enforceImageCap(db)
            return item
        }
        postChange()
        return decrypt(result)
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
        let hash = cipher.dedupHash(reference.path)
        let sealedBody = try cipher.seal(try reference.encodedJSON())
        let sealedApp = try sealOptional(sourceApp)
        let sealedBundle = try sealOptional(sourceBundleId)

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
                body: sealedBody,
                blobPath: nil,
                dimensions: nil,
                byteSize: Int(reference.byteSize),
                sourceApp: sealedApp,
                sourceBundleId: sealedBundle,
                createdAt: now,
                pinned: false,
                snippetId: nil,
                deletedAt: nil
            )
            try item.insert(db)
            return item
        }
        postChange()
        return decrypt(result)
    }

    /// Records a screen recording from a `VideoReference`. Dedupe is by path
    /// (re-recording over the same path is a no-op that bumps createdAt). The
    /// `.mov` lives in the user's Recordings folder — only `thumbnailBlobPath`
    /// (a small first-frame PNG blob, may be nil) is owned by the blob store.
    /// On a dedupe hit the existing thumbnail blob is kept and the new one is
    /// NOT swapped in (caller should delete the unused new blob, like
    /// `recordImage`). NO image-cap enforcement — videos are external files.
    @discardableResult
    func recordVideo(
        reference: VideoReference,
        thumbnailBlobPath: String?,
        sourceApp: String?
    ) throws -> Item? {
        let now = Int64(Date().timeIntervalSince1970)
        let hash = cipher.dedupHash(reference.path)
        let sealedBody = try cipher.seal(try reference.encodedJSON())
        let sealedApp = try sealOptional(sourceApp)
        let dimsString = "\(reference.width)x\(reference.height)"

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
                kind: "video",
                subtype: nil,
                contentHash: hash,
                body: sealedBody,
                blobPath: thumbnailBlobPath,
                dimensions: dimsString,
                byteSize: Int(reference.byteSize),
                sourceApp: sealedApp,
                sourceBundleId: nil,
                createdAt: now,
                pinned: false,
                snippetId: nil,
                deletedAt: nil
            )
            try item.insert(db)
            return item
        }
        postChange()
        return decrypt(result)
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
    /// Sensitive columns are decrypted before returning.
    func recentItems(limit: Int) throws -> [Item] {
        let rows = try queue.read { db in
            try Item
                .filter(Item.Columns.deletedAt == nil)
                .order(Item.Columns.createdAt.desc, Item.Columns.id.desc)
                .limit(limit)
                .fetchAll(db)
        }
        return rows.map(decrypt)
    }

    /// Every blob path referenced by any item row — including soft-deleted
    /// rows, which still own their blob until they are hard-deleted. Used by
    /// blob garbage collection to decide which on-disk files are orphans.
    func referencedBlobPaths() throws -> Set<String> {
        try queue.read { db in
            let paths = try String.fetchAll(
                db, sql: "SELECT blobPath FROM items WHERE blobPath IS NOT NULL"
            )
            return Set(paths)
        }
    }

    /// Hard-deletes image rows whose blob can no longer be read or decrypted
    /// (e.g. orphaned by a key mismatch from a re-signed/stale binary, or a
    /// corrupt/missing file). Such rows can only ever render as a blank
    /// placeholder, so they are removed along with their on-disk blob. Returns
    /// the number of rows pruned. Best-effort per row; a row that reads fine is
    /// left untouched.
    @discardableResult
    func pruneUndecryptableImages(blobStore: BlobStore) throws -> Int {
        let images = try queue.read { db in
            try Item
                .filter(Item.Columns.kind == "image" && Item.Columns.deletedAt == nil)
                .fetchAll(db)
        }
        var pruned = 0
        for item in images {
            guard let id = item.id, let path = item.blobPath else { continue }
            do {
                _ = try blobStore.read(relativePath: path)
            } catch {
                Log.app.error("pruning undecryptable image row \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                _ = try? queue.write { db in
                    try Item.filter(Item.Columns.id == id).deleteAll(db)
                }
                try? blobStore.delete(relativePath: path)
                pruned += 1
            }
        }
        if pruned > 0 { postChange() }
        return pruned
    }

    // MARK: - Soft delete

    /// Soft-deletes an item and, if it owns an image blob that no other live row
    /// references, eagerly deletes that blob file (instead of waiting for GC /
    /// retention). The row's `blobPath` is nulled so blob GC no longer counts it.
    func softDelete(itemId: Int64) throws {
        let now = Int64(Date().timeIntervalSince1970)
        let blobToDelete: String? = try queue.write { db -> String? in
            let row = try Item.filter(Item.Columns.id == itemId).fetchOne(db)
            try Item.filter(Item.Columns.id == itemId)
                .updateAll(db, [Item.Columns.deletedAt.set(to: now)])
            guard let path = row?.blobPath else { return nil }
            let stillReferenced = try Item
                .filter(Item.Columns.blobPath == path
                        && Item.Columns.deletedAt == nil
                        && Item.Columns.id != itemId)
                .fetchCount(db) > 0
            if stillReferenced { return nil }
            try Item.filter(Item.Columns.id == itemId)
                .updateAll(db, [Item.Columns.blobPath.set(to: nil)])
            return path
        }
        if let blobToDelete {
            do { try blobStore?.delete(relativePath: blobToDelete) }
            catch { Log.app.error("eager blob delete failed: \(error.localizedDescription, privacy: .public)") }
        }
        postChange()
    }

    /// Hard-deletes all non-pinned, non-soft-deleted items. Pinned items are
    /// preserved. Runs `VACUUM` afterwards so the deleted rows' bytes are
    /// reclaimed and not left recoverable in the database file.
    func clearAll() throws {
        _ = try queue.write { db in
            try Item.filter(Item.Columns.pinned == false && Item.Columns.deletedAt == nil)
                .deleteAll(db)
        }
        try queue.writeWithoutTransaction { db in try db.execute(sql: "VACUUM") }
        postChange()
    }

    func setPinned(itemId: Int64, pinned: Bool) throws {
        _ = try queue.write { db in
            try Item.filter(Item.Columns.id == itemId)
                .updateAll(db, [Item.Columns.pinned.set(to: pinned)])
            if pinned { try Self.enforcePinnedCap(db) }
        }
        postChange()
    }

    // MARK: - Caps

    /// Keeps at most `maxImages` non-pinned, non-deleted image rows, dropping
    /// the oldest. Set-based so it never round-trips ids through Swift.
    private static func enforceImageCap(_ db: Database) throws {
        try db.execute(sql: """
            DELETE FROM items
            WHERE kind = 'image' AND pinned = 0 AND deletedAt IS NULL
              AND id NOT IN (
                SELECT id FROM items
                WHERE kind = 'image' AND pinned = 0 AND deletedAt IS NULL
                ORDER BY createdAt DESC, id DESC
                LIMIT \(maxImages)
              )
            """)
    }

    /// Keeps at most `maxPinnedItems` pinned, non-deleted rows by unpinning the
    /// oldest. The rows survive (they re-enter normal history), only the pin is
    /// dropped.
    private static func enforcePinnedCap(_ db: Database) throws {
        try db.execute(sql: """
            UPDATE items SET pinned = 0
            WHERE pinned = 1 AND deletedAt IS NULL
              AND id NOT IN (
                SELECT id FROM items
                WHERE pinned = 1 AND deletedAt IS NULL
                ORDER BY createdAt DESC, id DESC
                LIMIT \(maxPinnedItems)
              )
            """)
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

    // MARK: - Field encryption

    private func sealOptional(_ s: String?) throws -> String? {
        guard let s else { return nil }
        return try cipher.seal(s)
    }

    /// Returns a copy of `item` with its sensitive columns decrypted, for handing
    /// back to callers/UI. Legacy plaintext fields pass through unchanged.
    private func decrypt(_ item: Item) -> Item {
        var copy = item
        copy.body = cipher.open(item.body)
        if let app = item.sourceApp { copy.sourceApp = cipher.open(app) }
        if let bundle = item.sourceBundleId { copy.sourceBundleId = cipher.open(bundle) }
        return copy
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
