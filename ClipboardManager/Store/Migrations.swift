// ClipboardManager/Store/Migrations.swift
import Foundation
import GRDB

enum Migrations {

    static func register(_ migrator: inout DatabaseMigrator) {

        migrator.registerMigration("v1-initial") { db in

            try db.create(table: "items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("subtype", .text)
                t.column("contentHash", .text).notNull().indexed()
                t.column("body", .text).notNull()
                t.column("blobPath", .text)
                t.column("dimensions", .text)
                t.column("byteSize", .integer).notNull().defaults(to: 0)
                t.column("sourceApp", .text)
                t.column("sourceBundleId", .text)
                t.column("createdAt", .integer).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("snippetId", .integer)
                t.column("deletedAt", .integer)
            }
            try db.create(index: "items_kind_createdAt",
                          on: "items", columns: ["kind", "createdAt"])
            try db.create(index: "items_pinned_snippetId",
                          on: "items", columns: ["pinned", "snippetId"])

            try db.create(table: "exclusions") { t in
                t.primaryKey("bundleId", .text)
                t.column("name", .text).notNull()
            }
        }

        migrator.registerMigration("v2-active-index") { db in
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS items_active_createdAt
                ON items (createdAt DESC)
                WHERE deletedAt IS NULL
                """)
        }
    }
}
