// ClipboardManager/Store/ItemKind.swift
import Foundation

/// Top-level type of a clipboard item. Phase 2 only records `.text(...)`.
/// `.image` and `.file` are reserved for Phase 3 and the monitor logs+skips
/// them for now.
enum ItemKind: Sendable, Equatable {
    case text(TextSubtype)
    case image
    case file
    case video
}

/// Persistable representation used by the database — strings rather than
/// associated-value enums, because GRDB columns are scalar.
extension ItemKind {

    /// Top-level kind string stored in the `kind` column.
    var kindColumn: String {
        switch self {
        case .text: return "text"
        case .image: return "image"
        case .file: return "file"
        case .video: return "video"
        }
    }

    /// Subtype string stored in the `subtype` column (nullable in SQL,
    /// optional here).
    var subtypeColumn: String? {
        switch self {
        case .text(let sub): return sub.rawValue
        case .image, .file, .video:  return nil
        }
    }

    /// Reconstruct from the two columns. Returns nil on unknown values.
    static func from(kind: String, subtype: String?) -> ItemKind? {
        switch kind {
        case "text":
            guard let sub = subtype.flatMap(TextSubtype.init(rawValue:)) else { return nil }
            return .text(sub)
        case "image":  return .image
        case "file":   return .file
        case "video":  return .video
        default:       return nil
        }
    }
}
