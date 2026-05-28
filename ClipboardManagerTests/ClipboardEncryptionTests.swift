import XCTest
import GRDB
import CryptoKit
@testable import ClipboardManager

final class ClipboardEncryptionTests: XCTestCase {

    private var dir: URL!
    private var dbPath: String!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clipenc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("clipboard.sqlite").path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func cipher(_ b: UInt8 = 3) -> FieldCipher {
        FieldCipher(masterKeyData: Data(repeating: b, count: 32))
    }

    /// Reads one column straight from the file with a PLAIN GRDB reader — no
    /// decryption — to inspect what is actually persisted on disk.
    private func rawColumn(_ name: String) throws -> String? {
        let raw = try DatabaseQueue(path: dbPath)
        return try raw.read { db in
            try String.fetchOne(db, sql: "SELECT \(name) FROM items LIMIT 1")
        }
    }

    func testBodyAndSourceAreEncryptedAtRest() throws {
        let store = try ClipboardStore(path: dbPath, cipher: cipher())
        _ = try store.recordText("TOP SECRET passphrase", sourceApp: "Notes", sourceBundleId: "com.apple.notes")

        let body = try rawColumn("body")
        XCTAssertNotEqual(body, "TOP SECRET passphrase")
        XCTAssertTrue(body?.hasPrefix("gcm1:") ?? false, "body must be sealed on disk")

        let app = try rawColumn("sourceApp")
        XCTAssertNotEqual(app, "Notes")
        XCTAssertTrue(app?.hasPrefix("gcm1:") ?? false, "source app must be sealed on disk")
    }

    func testContentHashIsKeyedNotPlainSHA256AtRest() throws {
        let store = try ClipboardStore(path: dbPath, cipher: cipher())
        _ = try store.recordText("1234", sourceApp: nil, sourceBundleId: nil)
        let stored = try rawColumn("contentHash")
        let plainSHA = SHA256.hash(data: Data("1234".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertNotEqual(stored, plainSHA, "dedup hash must be keyed, not a brute-forceable SHA256")
    }

    func testEncryptedFieldsRoundtripThroughRecentItems() throws {
        let store = try ClipboardStore(path: dbPath, cipher: cipher())
        _ = try store.recordText("café — naïve secret 🔐", sourceApp: "Safari", sourceBundleId: "com.apple.Safari")
        let items = try store.recentItems(limit: 10)
        XCTAssertEqual(items.first?.body, "café — naïve secret 🔐")
        XCTAssertEqual(items.first?.sourceApp, "Safari")
    }

    func testDedupeStillWorksWithKeyedHash() throws {
        let store = try ClipboardStore(path: dbPath, cipher: cipher())
        _ = try store.recordText("same content", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("same content", sourceApp: nil, sourceBundleId: nil)
        XCTAssertEqual(try store.countItems(), 1, "identical content must still dedupe to one row")
    }

    func testWrongKeyCannotRecoverBody() throws {
        do {
            let store = try ClipboardStore(path: dbPath, cipher: cipher(1))
            _ = try store.recordText("classified", sourceApp: nil, sourceBundleId: nil)
        }
        // Reopen with a different key: the body must NOT come back as plaintext.
        let other = try ClipboardStore(path: dbPath, cipher: cipher(2))
        let items = try other.recentItems(limit: 10)
        XCTAssertNotEqual(items.first?.body, "classified")
    }

    func testMigrationEncryptsExistingPlaintextRows() throws {
        // Seed a legacy plaintext row using a bare GRDB queue with the schema.
        do {
            let seed = try DatabaseQueue(path: dbPath)
            var migrator = DatabaseMigrator()
            Migrations.register(&migrator)
            try migrator.migrate(seed)
            try seed.write { db in
                try db.execute(
                    sql: "INSERT INTO items (kind, subtype, contentHash, body, byteSize, createdAt, pinned) VALUES ('text','plain',?,?,?,?,0)",
                    arguments: ["legacysha256hash", "my old plaintext secret", 23, 1000]
                )
            }
        }
        // Opening through ClipboardStore triggers the one-time encryption migration.
        let store = try ClipboardStore(path: dbPath, cipher: cipher())

        let body = try rawColumn("body")
        XCTAssertTrue(body?.hasPrefix("gcm1:") ?? false, "legacy row must be encrypted by migration")

        let items = try store.recentItems(limit: 10)
        XCTAssertEqual(items.first?.body, "my old plaintext secret",
                       "migrated row must still read back as its original plaintext")
    }
}
