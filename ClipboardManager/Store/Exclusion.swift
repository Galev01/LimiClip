// ClipboardManager/Store/Exclusion.swift
import Foundation
import GRDB

/// An app whose clipboard contents are never recorded.
struct Exclusion: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    static let databaseTableName = "exclusions"

    var bundleId: String     // primary key
    var name: String

    enum Columns {
        static let bundleId = Column(CodingKeys.bundleId)
        static let name     = Column(CodingKeys.name)
    }
}
