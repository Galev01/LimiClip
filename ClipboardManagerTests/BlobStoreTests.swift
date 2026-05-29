import XCTest
@testable import ClipboardManager

final class BlobStoreTests: XCTestCase {

    private var tempRoot: URL!
    private var store: BlobStore!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blobstore-tests-\(UUID().uuidString)", isDirectory: true)
        store = try BlobStore(rootDirectory: tempRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testWriteAndReadRoundtrip() throws {
        let data = Data("png-bytes-pretend".utf8)
        let relPath = try store.write(data: data, fileExtension: "png")
        XCTAssertTrue(relPath.hasSuffix(".png"))
        XCTAssertTrue(relPath.contains("/"))  // sharded

        let loaded = try store.read(relativePath: relPath)
        XCTAssertEqual(loaded, data)
    }

    func testShardingProduces2LevelDirectoryStructure() throws {
        let data = Data("x".utf8)
        let relPath = try store.write(data: data, fileExtension: "png")
        // Expect "ab/cd/uuid.png" — 2 shards of 2 chars each.
        let parts = relPath.split(separator: "/")
        XCTAssertEqual(parts.count, 3, "expected 3 path components, got \(relPath)")
        XCTAssertEqual(parts[0].count, 2)
        XCTAssertEqual(parts[1].count, 2)
    }

    func testWritesAreUniquePerCall() throws {
        let data = Data("identical".utf8)
        let p1 = try store.write(data: data, fileExtension: "png")
        let p2 = try store.write(data: data, fileExtension: "png")
        // BlobStore doesn't dedupe — that's ClipboardStore's job.
        XCTAssertNotEqual(p1, p2)
    }

    func testDeleteRemovesFile() throws {
        let path = try store.write(data: Data([1, 2, 3]), fileExtension: "png")
        try store.delete(relativePath: path)
        XCTAssertThrowsError(try store.read(relativePath: path))
    }

    func testReadMissingFileThrows() {
        XCTAssertThrowsError(try store.read(relativePath: "ff/ee/missing.png"))
    }

    func testPurgeOrphansDeletesOnlyUnreferencedFiles() throws {
        let keep = try store.write(data: Data([1, 2, 3]), fileExtension: "png")
        let orphan = try store.write(data: Data([4, 5, 6]), fileExtension: "png")

        let removed = try store.purgeOrphans(referenced: [keep])

        XCTAssertEqual(removed, [orphan])
        XCTAssertNoThrow(try store.read(relativePath: keep), "referenced file must survive")
        XCTAssertThrowsError(try store.read(relativePath: orphan), "orphan must be deleted")
    }

    func testPurgeOrphansWithEmptyReferenceDeletesEverything() throws {
        let a = try store.write(data: Data([1]), fileExtension: "png")
        let b = try store.write(data: Data([2]), fileExtension: "png")

        let removed = try store.purgeOrphans(referenced: [])

        XCTAssertEqual(Set(removed), Set([a, b]))
        XCTAssertThrowsError(try store.read(relativePath: a))
        XCTAssertThrowsError(try store.read(relativePath: b))
    }

    // MARK: - Encryption

    private func makeEncryptedStore() throws -> BlobStore {
        let cipher = FieldCipher(masterKeyData: Data(repeating: 9, count: 32))
        return try BlobStore(rootDirectory: tempRoot, cipher: cipher)
    }

    func testCipherEncryptsBytesOnDiskButRoundtrips() throws {
        let encStore = try makeEncryptedStore()
        let original = Data("a screenshot's worth of secret pixels".utf8)
        let relPath = try encStore.write(data: original, fileExtension: "png")

        // On-disk bytes must be ciphertext, not the original.
        let onDisk = try Data(contentsOf: encStore.absoluteURL(forRelativePath: relPath))
        XCTAssertNotEqual(onDisk, original, "blob must be encrypted at rest")
        XCTAssertFalse(onDisk.starts(with: Data("a screenshot".utf8)))

        // But reading through the store returns the original.
        XCTAssertEqual(try encStore.read(relativePath: relPath), original)
    }

    func testEncryptedStoreReadsLegacyPlaintextBlob() throws {
        // Simulate a blob written before encryption: a raw PNG on disk.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 42, 7])
        let relPath = try store.write(data: png, fileExtension: "png")  // plaintext store
        let encStore = try makeEncryptedStore()                          // same tempRoot
        XCTAssertEqual(try encStore.read(relativePath: relPath), png,
                       "legacy plaintext blobs must still read correctly after encryption ships")
    }

    // MARK: - Path-traversal confinement

    func testReadRejectsParentTraversal() throws {
        // Plant a secret file OUTSIDE the store root, a sibling of tempRoot.
        let secretURL = tempRoot.deletingLastPathComponent()
            .appendingPathComponent("secret-\(UUID().uuidString).txt")
        try Data("top secret".utf8).write(to: secretURL)
        defer { try? FileManager.default.removeItem(at: secretURL) }

        let escape = "../" + secretURL.lastPathComponent
        XCTAssertThrowsError(try store.read(relativePath: escape)) { error in
            XCTAssertEqual(error as? BlobStore.Failure, .pathEscapesRoot(escape))
        }
    }

    func testReadRejectsAbsolutePath() throws {
        let absolute = "/etc/hosts"
        XCTAssertThrowsError(try store.read(relativePath: absolute)) { error in
            XCTAssertEqual(error as? BlobStore.Failure, .pathEscapesRoot(absolute))
        }
    }

    func testDeleteRejectsParentTraversal() throws {
        let victimURL = tempRoot.deletingLastPathComponent()
            .appendingPathComponent("victim-\(UUID().uuidString).txt")
        try Data("do not delete".utf8).write(to: victimURL)
        defer { try? FileManager.default.removeItem(at: victimURL) }

        let escape = "../" + victimURL.lastPathComponent
        XCTAssertThrowsError(try store.delete(relativePath: escape)) { error in
            XCTAssertEqual(error as? BlobStore.Failure, .pathEscapesRoot(escape))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: victimURL.path),
                      "file outside root must not be deleted")
    }

    func testAbsoluteURLRejectsParentTraversal() throws {
        let escape = "../../etc/passwd"
        XCTAssertThrowsError(try store.absoluteURL(forRelativePath: escape)) { error in
            XCTAssertEqual(error as? BlobStore.Failure, .pathEscapesRoot(escape))
        }
    }

    func testAbsoluteURLAllowsValidShardedPath() throws {
        let relPath = try store.write(data: Data([1, 2, 3]), fileExtension: "png")
        let url = try store.absoluteURL(forRelativePath: relPath)
        let base = tempRoot.resolvingSymlinksInPath().path
        XCTAssertTrue(url.resolvingSymlinksInPath().path.hasPrefix(base),
                      "valid blob URL must stay under root")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testReadRejectsEmptyPath() {
        XCTAssertThrowsError(try store.read(relativePath: "")) { error in
            XCTAssertEqual(error as? BlobStore.Failure, .pathEscapesRoot(""))
        }
    }

    func testValidRoundtripStillWorksAfterGuard() throws {
        let data = Data("normal blob".utf8)
        let relPath = try store.write(data: data, fileExtension: "png")
        XCTAssertEqual(try store.read(relativePath: relPath), data)
        try store.delete(relativePath: relPath)
        XCTAssertThrowsError(try store.read(relativePath: relPath))
    }
}
