// ClipboardManager/Store/Item.swift
import Foundation
import GRDB

/// A single clipboard history entry. One row in `items`.
///
/// `body` holds the text content for `.text` items, or a JSON-encoded file
/// reference for `.file` items (Phase 3). For `.image` items, `body` is the
/// blob path (Phase 3).
struct Item: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    static let databaseTableName = "items"

    var id: Int64?
    var kind: String                    // ItemKind.kindColumn
    var subtype: String?                // ItemKind.subtypeColumn
    var contentHash: String             // SHA256 hex of canonical body
    var body: String                    // text body / blob path / file path JSON
    var blobPath: String?               // images only (Phase 3) — nil in Phase 2
    var dimensions: String?             // "WxH" — Phase 3
    var byteSize: Int                   // body bytes
    var sourceApp: String?              // display name of frontmost app
    var sourceBundleId: String?         // bundle id at copy time
    var createdAt: Int64                // unix epoch seconds
    var pinned: Bool                    // 0/1 — Phase 5 will use this
    var snippetId: Int64?               // FK → snippets.id — Phase 5
    var deletedAt: Int64?               // soft delete — set when user deletes

    /// GRDB column names — keep in sync with the table definition.
    enum Columns {
        static let id             = Column(CodingKeys.id)
        static let kind           = Column(CodingKeys.kind)
        static let subtype        = Column(CodingKeys.subtype)
        static let contentHash    = Column(CodingKeys.contentHash)
        static let body           = Column(CodingKeys.body)
        static let blobPath       = Column(CodingKeys.blobPath)
        static let dimensions     = Column(CodingKeys.dimensions)
        static let byteSize       = Column(CodingKeys.byteSize)
        static let sourceApp      = Column(CodingKeys.sourceApp)
        static let sourceBundleId = Column(CodingKeys.sourceBundleId)
        static let createdAt      = Column(CodingKeys.createdAt)
        static let pinned         = Column(CodingKeys.pinned)
        static let snippetId      = Column(CodingKeys.snippetId)
        static let deletedAt      = Column(CodingKeys.deletedAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Convenience: reconstitute the strongly-typed kind from columns.
    var typedKind: ItemKind? {
        ItemKind.from(kind: kind, subtype: subtype)
    }
}
