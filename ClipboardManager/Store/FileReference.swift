import Foundation

/// Persisted JSON-in-body representation of a file copied from Finder.
/// We don't dereference the file at copy time — the user could move/rename
/// it later. We only record the path snapshot.
struct FileReference: Codable, Equatable, Sendable {
    let path: String
    let name: String
    let byteSize: Int64
    let modifiedAt: Int64       // unix epoch seconds, file mtime at copy time

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteSize)
    }

    /// Encode to compact JSON for storage in the Item.body column.
    func encodedJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Decode from a JSON string previously produced by `encodedJSON()`.
    static func decodingJSON(_ raw: String) throws -> FileReference {
        guard let data = raw.data(using: .utf8) else {
            throw NSError(domain: "FileReference", code: 1, userInfo: [NSLocalizedDescriptionKey: "non-UTF8 body"])
        }
        return try JSONDecoder().decode(FileReference.self, from: data)
    }
}
