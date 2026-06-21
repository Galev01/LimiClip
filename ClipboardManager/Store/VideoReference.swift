import Foundation

/// Persisted JSON-in-body representation of a screen recording. Like
/// `FileReference`, we don't dereference the file later — we record a path
/// snapshot plus the metadata needed to render a video card (duration +
/// pixel dimensions) without re-reading the `.mov` every time the drawer opens.
/// The `.mov` lives in the user's Recordings folder, NOT in the encrypted
/// blob store — only a small first-frame thumbnail is stored as a blob.
struct VideoReference: Codable, Equatable, Sendable {
    let path: String
    let name: String
    let byteSize: Int64
    let modifiedAt: Int64       // unix epoch seconds, file mtime at record time
    let durationSeconds: Double
    let width: Int
    let height: Int

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteSize)
    }

    /// Duration as "M:SS" (e.g. 65s → "1:05", 5s → "0:05").
    var formattedDuration: String {
        let total = max(0, Int(durationSeconds.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Encode to compact JSON for storage in the Item.body column.
    func encodedJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Decode from a JSON string previously produced by `encodedJSON()`.
    static func decodingJSON(_ raw: String) throws -> VideoReference {
        guard let data = raw.data(using: .utf8) else {
            throw NSError(domain: "VideoReference", code: 1, userInfo: [NSLocalizedDescriptionKey: "non-UTF8 body"])
        }
        return try JSONDecoder().decode(VideoReference.self, from: data)
    }
}
