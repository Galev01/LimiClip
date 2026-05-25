# Clipboard Manager — Phase 2 Implementation Plan (Pasteboard pipeline)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the drawer actually show what the user copied. When the user copies text in any other app, that text shows up as a horizontal card in the drawer. History persists across launches (encrypted SQLite). Duplicates collapse. Items from password managers are skipped. Retention purges old items hourly.

**Scope (Phase 2):** TEXT items only. Image and file capture are Phase 3 — we'll detect their presence on the pasteboard but skip them with a log line for now. UI for cards stays minimal but functional: a simple horizontal scroll of text-only cards using `ClipboardCard` styling already shown in the design (full polish — hover preview, context menu, search, tabs — comes in Phase 4).

**Architecture:**

- `ClipboardStore` owns a GRDB+SQLCipher database in Application Support. Key in Keychain. Migrations are schema-versioned.
- `PasteboardMonitor` polls `NSPasteboard.general.changeCount` on a 250 ms `Timer` on the main runloop. On change, it reads, classifies, applies privacy filters, computes a content hash, and inserts via the store (which dedupes by hash).
- `RetentionJob` runs every 60 minutes (and once at app launch) — prunes items past the retention policy.
- A `@MainActor` `ClipboardViewModel` is the single SwiftUI source of truth for the drawer. It subscribes to store change events and republishes the visible list.
- The drawer becomes data-driven: empty state when no items; horizontal `ScrollView` of `ClipboardCard` text views otherwise.

**Tech Stack additions:**
- `GRDB.swift` SPM package (version 7.x) using the `GRDB-SQLCipher` product (bundles SQLCipher; transparent encryption via `Configuration.prepareDatabase { db in try db.usePassphrase(...) }`).

**Verification target:** At the end of Phase 2, copying text in another app makes a card appear in the drawer within ~300 ms. Killing and relaunching the app shows the same items. Copying from a known password manager (1Password / Bitwarden) does NOT create an item. Copying twice (same content) does not duplicate. After 24 simulated hours' worth of items beyond the retention cap, the oldest items are removed automatically.

---

## File Structure

```
ClipboardManager/
├── Services/
│   ├── PasteboardMonitor.swift      (NEW)
│   └── RetentionJob.swift           (NEW)
├── Store/
│   ├── ClipboardStore.swift         (NEW — orchestrates DB + Keychain key)
│   ├── DatabaseKey.swift            (NEW — Keychain-backed encryption key)
│   ├── Migrations.swift             (NEW — schema versioning via GRDB)
│   ├── Item.swift                   (NEW — Codable record type)
│   ├── ItemKind.swift               (NEW — text/image/file enum + subtype)
│   ├── Exclusion.swift              (NEW — Codable record)
│   └── DefaultExclusions.swift      (NEW — seed list)
├── ActionsKit/
│   └── SubtypeDetector.swift        (NEW — url? code? json? on text)
├── UI/
│   └── Drawer/
│       ├── ClipboardCard.swift      (NEW — TEXT-ONLY rendering for Phase 2)
│       └── DrawerView.swift         (MODIFIED — wire to view model)
├── App/
│   └── AppCoordinator.swift         (MODIFIED — boots store + monitor + retention)
└── ClipboardViewModel.swift         (NEW — @MainActor ObservableObject)

ClipboardManagerTests/
├── SubtypeDetectorTests.swift       (NEW)
├── ClipboardStoreTests.swift        (NEW — uses tmp directory + in-memory key)
├── PasteboardMonitorTests.swift     (NEW — uses NSPasteboard.withUniqueName())
├── RetentionTests.swift             (NEW)
└── DefaultExclusionsTests.swift     (NEW)
```

Why this split: store concerns (key management, migrations, records) live in `Store/` and each file owns one concept. Monitor + retention live under `Services/`. UI knows only about `ClipboardViewModel`, not GRDB. `ItemKind` is its own file so Phase 3 can extend it without touching the record type.

---

## Pre-flight

```bash
cd /Users/gal.lev/Clipboard
git log --oneline -1   # should be c8cd329
git tag -l             # should include v0.1.0-phase1
```

---

## Task 1: Add GRDB + SQLCipher SPM dependency

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Edit `project.yml`** to add the GRDB package under `packages:` and add it as a dependency of the `ClipboardManager` target.

In the `packages:` section, add a new entry below `KeyboardShortcuts`:

```yaml
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: "7.0.0"
    product: GRDB-SQLCipher
```

NOTE: as of GRDB 7.x, the SQLCipher-bundling product is exposed via a separate target inside the same package. If the `from: "7.0.0"` resolution fails because SQLCipher is gated behind a flag, fall back to:

```yaml
  GRDB:
    url: https://github.com/duckduckgo/GRDB.swift
    branch: SQLCipher_4.5.5
```

(That fork is what the GRDB readme recommends for projects that need bundled SQLCipher.) Use the official package first; only switch if the build fails to resolve the `GRDB-SQLCipher` product.

In the `ClipboardManager` target's `dependencies:` block, change from:

```yaml
    dependencies:
      - package: KeyboardShortcuts
```

to:

```yaml
    dependencies:
      - package: KeyboardShortcuts
      - package: GRDB
        product: GRDB
```

If the official GRDB.swift 7.x exposes the SQLCipher product as `GRDB-SQLCipher` (verify via `swift package describe` after a manual `swift package resolve`), change the product line to `GRDB-SQLCipher`. The Swift `import` is `import GRDB` either way.

- [ ] **Step 2: Regenerate + resolve packages**

```bash
xcodegen generate
xcodebuild -resolvePackageDependencies -project ClipboardManager.xcodeproj -scheme ClipboardManager 2>&1 | tail -10
```

Expected: `Resolved source packages:` lists GRDB.

- [ ] **Step 3: Build** (no source code uses GRDB yet, but the package must link)

```bash
make build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add project.yml
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "deps: add GRDB.swift (with SQLCipher) SPM package"
```

---

## Task 2: SubtypeDetector (TDD)

This is the only piece of pure logic in Phase 2 that doesn't need infrastructure to test. Build it first.

**Files:**
- Create: `ClipboardManager/ActionsKit/SubtypeDetector.swift`
- Create: `ClipboardManagerTests/SubtypeDetectorTests.swift`

- [ ] **Step 1: Failing test**

```swift
// ClipboardManagerTests/SubtypeDetectorTests.swift
import XCTest
@testable import ClipboardManager

final class SubtypeDetectorTests: XCTestCase {

    func testDetectsURL() {
        XCTAssertEqual(SubtypeDetector.detect("https://example.com"), .url)
        XCTAssertEqual(SubtypeDetector.detect("http://example.com/path?q=1"), .url)
        XCTAssertEqual(SubtypeDetector.detect("https://github.com/user/repo/pull/42"), .url)
    }

    func testRejectsNonURLTextThatLooksUrlish() {
        XCTAssertNotEqual(SubtypeDetector.detect("see https://example.com for details"), .url)
        XCTAssertNotEqual(SubtypeDetector.detect("https://x"), .url) // too short / no TLD
    }

    func testDetectsJSON() {
        XCTAssertEqual(SubtypeDetector.detect("{\"a\": 1}"), .json)
        XCTAssertEqual(SubtypeDetector.detect("[1, 2, 3]"), .json)
        XCTAssertEqual(SubtypeDetector.detect("  {\n  \"name\": \"x\"\n}  "), .json)
    }

    func testRejectsInvalidJSON() {
        XCTAssertNotEqual(SubtypeDetector.detect("{a: 1}"), .json)
        XCTAssertNotEqual(SubtypeDetector.detect("just curly { and brackets ]"), .json)
    }

    func testDetectsCode() {
        XCTAssertEqual(SubtypeDetector.detect("func foo() {\n    return 42\n}"), .code)
        XCTAssertEqual(SubtypeDetector.detect("def hello():\n    print('hi')"), .code)
        XCTAssertEqual(SubtypeDetector.detect("const x = await fetch('/api');"), .code)
        XCTAssertEqual(SubtypeDetector.detect("SELECT * FROM users WHERE id = 1;"), .code)
    }

    func testPlainFallback() {
        XCTAssertEqual(SubtypeDetector.detect("Hey team, can we meet Thursday?"), .plain)
        XCTAssertEqual(SubtypeDetector.detect("1600 Amphitheatre Parkway"), .plain)
    }

    func testEmptyAndWhitespaceArePlain() {
        XCTAssertEqual(SubtypeDetector.detect(""), .plain)
        XCTAssertEqual(SubtypeDetector.detect("   \n  "), .plain)
    }
}
```

- [ ] **Step 2: Run, verify fails** — `Cannot find 'SubtypeDetector'`.

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/ActionsKit/SubtypeDetector.swift
import Foundation

/// Classifies text into a presentation subtype. Used at insert time only —
/// we record the detected subtype with the item so the UI doesn't have to
/// re-classify on every render.
enum TextSubtype: String, Codable, Sendable {
    case plain
    case url
    case json
    case code
}

enum SubtypeDetector {

    /// Heuristic classification, evaluated in order: URL → JSON → code → plain.
    static func detect(_ text: String) -> TextSubtype {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .plain }

        if isWholeStringURL(trimmed) { return .url }
        if isJSON(trimmed) { return .json }
        if looksLikeCode(trimmed) { return .code }
        return .plain
    }

    // MARK: - URL

    private static func isWholeStringURL(_ s: String) -> Bool {
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              host.contains(".")            // must have a TLD-like dot
        else { return false }
        // No internal whitespace. detect() already trimmed external whitespace.
        return !s.contains(where: { $0.isWhitespace })
    }

    // MARK: - JSON

    private static func isJSON(_ s: String) -> Bool {
        guard let first = s.first, (first == "{" || first == "["),
              let data = s.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    // MARK: - Code

    /// Looks for any of: language keywords near the start, common code punctuation,
    /// or shell prompt prefixes.
    private static func looksLikeCode(_ s: String) -> Bool {
        // Multi-line with braces or semicolons is a strong signal.
        let multiLine = s.contains("\n")
        let hasCodeChars = s.contains("{") && s.contains("}")
            || s.contains(";")
            || s.contains("=>")
            || s.contains("->")

        // First non-whitespace token starts with a keyword we recognise.
        let firstWord = s.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        let codeStarters: Set<String> = [
            "func", "def", "fn", "class", "struct", "enum", "interface", "type",
            "import", "from", "package", "module", "namespace",
            "const", "let", "var", "private", "public", "static", "final",
            "if", "for", "while", "switch", "case", "return", "throw", "try",
            "async", "await", "yield",
            "select", "insert", "update", "delete", "create", "drop", "alter",
            "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
        ]
        if codeStarters.contains(firstWord) { return true }

        // Shell pipelines / command lines often start with a known command.
        let shellStarters: Set<String> = [
            "brew", "npm", "yarn", "pnpm", "pip", "git", "docker",
            "curl", "wget", "ssh", "scp", "make", "cargo", "go", "python", "node", "ruby",
            "sudo", "open", "cd", "ls", "mv", "cp", "rm", "echo", "cat", "grep", "awk", "sed",
        ]
        if shellStarters.contains(firstWord) && hasCodeChars { return true }
        if shellStarters.contains(firstWord) && s.split(separator: " ").count > 1 { return true }

        // Heavy punctuation across multiple lines: probably code.
        if multiLine && hasCodeChars { return true }

        return false
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/ActionsKit/SubtypeDetector.swift ClipboardManagerTests/SubtypeDetectorTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "actions: text subtype detector (url/json/code/plain)"
```

---

## Task 3: ItemKind + TextSubtype types

`TextSubtype` already exists from Task 2. Now add the broader `ItemKind` enum that wraps it.

**Files:**
- Create: `ClipboardManager/Store/ItemKind.swift`

- [ ] **Step 1: Implement**

```swift
// ClipboardManager/Store/ItemKind.swift
import Foundation

/// Top-level type of a clipboard item. Phase 2 only records `.text(...)`.
/// `.image` and `.file` are reserved for Phase 3 and the monitor logs+skips
/// them for now.
enum ItemKind: Sendable, Equatable {
    case text(TextSubtype)
    case image
    case file
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
        }
    }

    /// Subtype string stored in the `subtype` column (nullable in SQL,
    /// optional here).
    var subtypeColumn: String? {
        switch self {
        case .text(let sub): return sub.rawValue
        case .image, .file:  return nil
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
        default:       return nil
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
make build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/Store/ItemKind.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "store: ItemKind + column round-trip"
```

---

## Task 4: Item record type

**Files:**
- Create: `ClipboardManager/Store/Item.swift`

- [ ] **Step 1: Implement**

```swift
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
```

- [ ] **Step 2: Build**

```bash
make build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/Store/Item.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "store: Item record (GRDB Codable + FetchableRecord)"
```

---

## Task 5: Exclusion record + default seed list

**Files:**
- Create: `ClipboardManager/Store/Exclusion.swift`
- Create: `ClipboardManager/Store/DefaultExclusions.swift`
- Create: `ClipboardManagerTests/DefaultExclusionsTests.swift`

- [ ] **Step 1: Failing test**

```swift
// ClipboardManagerTests/DefaultExclusionsTests.swift
import XCTest
@testable import ClipboardManager

final class DefaultExclusionsTests: XCTestCase {

    func testIncludesKnownPasswordManagers() {
        let bundles = DefaultExclusions.list.map(\.bundleId)
        XCTAssertTrue(bundles.contains("com.agilebits.onepassword7"))
        XCTAssertTrue(bundles.contains("com.1password.1password8"))
        XCTAssertTrue(bundles.contains("com.bitwarden.desktop"))
        XCTAssertTrue(bundles.contains("com.apple.keychainaccess"))
    }

    func testEveryEntryHasName() {
        for e in DefaultExclusions.list {
            XCTAssertFalse(e.name.isEmpty, "\(e.bundleId) has empty name")
        }
    }

    func testNoDuplicateBundleIds() {
        let bundles = DefaultExclusions.list.map(\.bundleId)
        XCTAssertEqual(bundles.count, Set(bundles).count)
    }
}
```

- [ ] **Step 2: Run, verify fails**

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 3: Implement Exclusion**

```swift
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
```

- [ ] **Step 4: Implement DefaultExclusions**

```swift
// ClipboardManager/Store/DefaultExclusions.swift
import Foundation

enum DefaultExclusions {
    /// Seeded into the `exclusions` table on first launch. The user can
    /// remove any of these from Preferences (Phase 7).
    static let list: [Exclusion] = [
        Exclusion(bundleId: "com.agilebits.onepassword7", name: "1Password 7"),
        Exclusion(bundleId: "com.1password.1password8",   name: "1Password"),
        Exclusion(bundleId: "com.bitwarden.desktop",      name: "Bitwarden"),
        Exclusion(bundleId: "com.apple.keychainaccess",   name: "Keychain Access"),
        Exclusion(bundleId: "com.lastpass.LastPass",      name: "LastPass"),
        Exclusion(bundleId: "com.dashlane.dashlanephonefinalmac", name: "Dashlane"),
    ]
}
```

- [ ] **Step 5: Tests pass**

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add ClipboardManager/Store/Exclusion.swift ClipboardManager/Store/DefaultExclusions.swift ClipboardManagerTests/DefaultExclusionsTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "store: Exclusion record + default password-manager seed list"
```

---

## Task 6: Database encryption key in Keychain

**Files:**
- Create: `ClipboardManager/Store/DatabaseKey.swift`

We need a stable 32-byte random key, persisted in Keychain so the DB can be opened on subsequent launches. The key is generated on first launch and never logged.

- [ ] **Step 1: Implement**

```swift
// ClipboardManager/Store/DatabaseKey.swift
import Foundation
import Security
import CryptoKit

/// Manages the AES-256 passphrase used to open the encrypted SQLite database.
/// The key is generated once and stored in the user's Keychain so subsequent
/// launches can reopen the database.
enum DatabaseKey {

    private static let service = "dev.gallev.ClipboardManager.db-key"
    private static let account = "primary"

    enum Failure: Error, CustomStringConvertible {
        case keychain(OSStatus)
        case generation

        var description: String {
            switch self {
            case .keychain(let s): return "Keychain error: \(s)"
            case .generation: return "Failed to generate random key"
            }
        }
    }

    /// Returns the existing key from Keychain, generating + storing a fresh
    /// one if none exists.
    static func loadOrCreate() throws -> Data {
        if let existing = try loadFromKeychain() {
            return existing
        }
        let key = try generate()
        try storeInKeychain(key)
        return key
    }

    // MARK: - Internals

    private static func generate() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw Failure.generation }
        return Data(bytes)
    }

    private static func loadFromKeychain() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecReturnData as String:      true,
            kSecMatchLimit as String:      kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keychain(status)
        }
    }

    private static func storeInKeychain(_ key: Data) throws {
        let attrs: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecAttrAccessible as String:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:       key,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    /// Removes the key from Keychain. Used by tests; not exposed to users.
    /// After removal, any existing DB file becomes unreadable.
    static func deleteForTests() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 2: Build**

```bash
make build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/Store/DatabaseKey.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "store: DatabaseKey — 32-byte AES key persisted in Keychain"
```

---

## Task 7: Migrations

**Files:**
- Create: `ClipboardManager/Store/Migrations.swift`

- [ ] **Step 1: Implement**

```swift
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
    }
}
```

- [ ] **Step 2: Build**

```bash
make build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/Store/Migrations.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "store: schema migrations (items + exclusions, v1)"
```

---

## Task 8: ClipboardStore (TDD)

**Files:**
- Create: `ClipboardManager/Store/ClipboardStore.swift`
- Create: `ClipboardManagerTests/ClipboardStoreTests.swift`

This is the central data class. Tests will use an in-memory database via `DatabaseQueue()` and a per-test temp key.

- [ ] **Step 1: Failing tests**

```swift
// ClipboardManagerTests/ClipboardStoreTests.swift
import XCTest
import GRDB
@testable import ClipboardManager

final class ClipboardStoreTests: XCTestCase {

    private func makeStore() throws -> ClipboardStore {
        // In-memory DB, fresh per test. Use a constant key — not Keychain.
        let cfg = ClipboardStore.testingConfiguration()
        return try ClipboardStore(configuration: cfg)
    }

    func testInsertCreatesRow() throws {
        let store = try makeStore()
        let inserted = try store.recordText(
            "hello world",
            sourceApp: "TestApp",
            sourceBundleId: "test.app"
        )
        XCTAssertNotNil(inserted)
        XCTAssertEqual(try store.countItems(), 1)
    }

    func testInsertDedupesByContentHash() throws {
        let store = try makeStore()
        let first = try store.recordText("same", sourceApp: nil, sourceBundleId: nil)
        // Re-insert identical content.
        let second = try store.recordText("same", sourceApp: nil, sourceBundleId: nil)
        XCTAssertEqual(try store.countItems(), 1)
        XCTAssertEqual(first?.id, second?.id)
        // createdAt should have advanced.
        XCTAssertGreaterThanOrEqual(second?.createdAt ?? 0, first?.createdAt ?? 0)
    }

    func testRecentItemsAreOrderedNewestFirst() throws {
        let store = try makeStore()
        _ = try store.recordText("oldest", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("middle", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("newest", sourceApp: nil, sourceBundleId: nil)
        let recent = try store.recentItems(limit: 10)
        XCTAssertEqual(recent.map(\.body), ["newest", "middle", "oldest"])
    }

    func testEmptyAndWhitespaceItemsRejected() throws {
        let store = try makeStore()
        XCTAssertNil(try store.recordText("", sourceApp: nil, sourceBundleId: nil))
        XCTAssertNil(try store.recordText("    \n   ", sourceApp: nil, sourceBundleId: nil))
        XCTAssertEqual(try store.countItems(), 0)
    }

    func testSeedDefaultExclusionsRunsOnce() throws {
        let store = try makeStore()
        try store.seedDefaultExclusionsIfNeeded()
        let firstCount = try store.allExclusions().count
        XCTAssertGreaterThan(firstCount, 0)
        // Idempotent.
        try store.seedDefaultExclusionsIfNeeded()
        let secondCount = try store.allExclusions().count
        XCTAssertEqual(firstCount, secondCount)
    }

    func testExcludedBundleIdSkipped() throws {
        let store = try makeStore()
        try store.addExclusion(bundleId: "com.bad.app", name: "Bad App")
        let result = try store.recordText("secret", sourceApp: "Bad App", sourceBundleId: "com.bad.app")
        XCTAssertNil(result)
        XCTAssertEqual(try store.countItems(), 0)
    }

    func testSoftDelete() throws {
        let store = try makeStore()
        let inserted = try store.recordText("temporary", sourceApp: nil, sourceBundleId: nil)
        try store.softDelete(itemId: inserted!.id!)
        XCTAssertEqual(try store.recentItems(limit: 10).count, 0)
        XCTAssertEqual(try store.countItems(includingDeleted: true), 1)
    }

    func testPurgeRemovesItemsOlderThanRetentionWindow() throws {
        let store = try makeStore()
        // Force-insert with a stale timestamp.
        let stale = Int64(Date().timeIntervalSince1970) - 60 * 60 * 24 * 200  // 200 days ago
        try store.testingInsertStaleItem(body: "old", createdAt: stale)
        _ = try store.recordText("fresh", sourceApp: nil, sourceBundleId: nil)

        try store.purgeOlderThan(days: 90)
        let recent = try store.recentItems(limit: 100)
        XCTAssertEqual(recent.map(\.body), ["fresh"])
    }

    func testPurgeRemovesItemsBeyondMaxCount() throws {
        let store = try makeStore()
        for i in 0..<20 {
            _ = try store.recordText("item-\(i)", sourceApp: nil, sourceBundleId: nil)
        }
        try store.purgeBeyondCount(max: 10)
        XCTAssertEqual(try store.recentItems(limit: 100).count, 10)
        // Newest 10 retained.
        let bodies = try store.recentItems(limit: 100).map(\.body)
        XCTAssertEqual(bodies.first, "item-19")
        XCTAssertEqual(bodies.last, "item-10")
    }
}
```

- [ ] **Step 2: Run, verify fails** with "Cannot find 'ClipboardStore'".

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 3: Implement ClipboardStore**

```swift
// ClipboardManager/Store/ClipboardStore.swift
import Foundation
import GRDB
import CryptoKit

/// Thread-safe SQLite-backed store for clipboard history.
///
/// Backed by GRDB+SQLCipher. The encryption key lives in the user's Keychain
/// (see `DatabaseKey`). The store is `Sendable` because it wraps a
/// `DatabaseQueue` which serialises all access.
final class ClipboardStore: @unchecked Sendable {

    private let queue: any DatabaseWriter

    // MARK: - Initialisation

    /// Production init: opens the encrypted file in Application Support,
    /// generates+stores a key on first launch.
    convenience init() throws {
        let key = try DatabaseKey.loadOrCreate()
        var cfg = Configuration()
        cfg.prepareDatabase { db in
            try db.usePassphrase(key)
        }
        let url = try Self.databaseURL()
        let queue = try DatabaseQueue(path: url.path, configuration: cfg)
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

    /// Application Support / Clipboard Manager / clipboard.sqlcipher
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
        return dir.appendingPathComponent("clipboard.sqlcipher", isDirectory: false)
    }

    // MARK: - Test helpers

    /// In-memory configuration with no passphrase. For unit tests only.
    static func testingConfiguration() -> Configuration {
        // Intentionally not encrypted — we are exercising schema + logic.
        return Configuration()
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

        return try queue.write { db in
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
                .order(Item.Columns.createdAt.desc)
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
    }

    /// Keep at most `max` non-pinned items, ordered by createdAt desc. Older
    /// non-pinned items are hard-deleted.
    func purgeBeyondCount(max: Int) throws {
        _ = try queue.write { db in
            let keepIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM items
                WHERE deletedAt IS NULL AND pinned = 0
                ORDER BY createdAt DESC
                LIMIT \(max)
                """)
            if keepIds.isEmpty {
                try Item.filter(Item.Columns.pinned == false).deleteAll(db)
            } else {
                try Item.filter(!keepIds.contains(Item.Columns.id) && Item.Columns.pinned == false)
                    .deleteAll(db)
            }
        }
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
    }

    func removeExclusion(bundleId: String) throws {
        _ = try queue.write { db in
            try Exclusion.deleteOne(db, key: bundleId)
        }
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
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Store/ClipboardStore.swift ClipboardManagerTests/ClipboardStoreTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "store: ClipboardStore (record/dedupe/query/purge/exclusions) + tests"
```

---

## Task 9: PasteboardMonitor (TDD)

**Files:**
- Create: `ClipboardManager/Services/PasteboardMonitor.swift`
- Create: `ClipboardManagerTests/PasteboardMonitorTests.swift`

The monitor polls `NSPasteboard.changeCount`. Tests use `NSPasteboard.withUniqueName()` to avoid touching the user's actual pasteboard.

- [ ] **Step 1: Failing tests**

```swift
// ClipboardManagerTests/PasteboardMonitorTests.swift
import XCTest
import AppKit
@testable import ClipboardManager

@MainActor
final class PasteboardMonitorTests: XCTestCase {

    private var pasteboard: NSPasteboard!
    private var store: ClipboardStore!
    private var monitor: PasteboardMonitor!

    override func setUp() async throws {
        try await super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
        store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    }

    override func tearDown() async throws {
        monitor?.stop()
        pasteboard?.releaseGlobally()
        try await super.tearDown()
    }

    func testCapturesNewTextOnPasteboardChange() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()  // baseline snapshot

        pasteboard.clearContents()
        pasteboard.setString("hello pasteboard", forType: .string)

        monitor.tickForTesting()

        XCTAssertEqual(try store.recentItems(limit: 5).map(\.body), ["hello pasteboard"])
    }

    func testSkipsConcealedItems() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()

        pasteboard.clearContents()
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        pasteboard.setData(Data("don't capture me".utf8), forType: concealed)
        pasteboard.setString("don't capture me", forType: .string)

        monitor.tickForTesting()

        XCTAssertEqual(try store.countItems(), 0)
    }

    func testSkipsFromExcludedBundle() async throws {
        try store.addExclusion(bundleId: "com.evil.copier", name: "Evil")

        monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            store: store,
            frontmostApp: { ("Evil", "com.evil.copier") }
        )
        monitor.tickForTesting()

        pasteboard.clearContents()
        pasteboard.setString("secret", forType: .string)
        monitor.tickForTesting()

        XCTAssertEqual(try store.countItems(), 0)
    }

    func testPauseBypassesCapture() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()

        monitor.pause(until: Date().addingTimeInterval(60))

        pasteboard.clearContents()
        pasteboard.setString("while paused", forType: .string)
        monitor.tickForTesting()

        XCTAssertEqual(try store.countItems(), 0)

        // Lift pause and re-copy.
        monitor.pause(until: Date.distantPast)
        pasteboard.clearContents()
        pasteboard.setString("after pause", forType: .string)
        monitor.tickForTesting()
        XCTAssertEqual(try store.recentItems(limit: 5).map(\.body), ["after pause"])
    }

    func testIgnoresImagesInPhase2() async throws {
        monitor = PasteboardMonitor(pasteboard: pasteboard, store: store, frontmostApp: { (nil, nil) })
        monitor.tickForTesting()

        pasteboard.clearContents()
        let tinyTIFF: Data = {
            // 1x1 black TIFF — actual bytes don't matter; we only care the
            // monitor sees a non-text type and skips it without crashing.
            let image = NSImage(size: NSSize(width: 1, height: 1))
            image.lockFocus()
            NSColor.black.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1))
            image.unlockFocus()
            return image.tiffRepresentation ?? Data()
        }()
        pasteboard.setData(tinyTIFF, forType: .tiff)

        monitor.tickForTesting()
        XCTAssertEqual(try store.countItems(), 0)
    }
}
```

- [ ] **Step 2: Run, verify fails** — `Cannot find 'PasteboardMonitor'`.

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/Services/PasteboardMonitor.swift
import AppKit
import Foundation

/// Polls `NSPasteboard.changeCount` every 250 ms and records text changes
/// into the `ClipboardStore`. Filters: concealed pasteboard types, excluded
/// bundle IDs, paused-until timestamp, and (Phase 2 only) non-text content.
@MainActor
final class PasteboardMonitor {

    static let pollInterval: TimeInterval = 0.25

    /// Provider for the frontmost app's display name + bundle id at the moment
    /// of a pasteboard change. Injectable for tests.
    typealias FrontmostAppProvider = () -> (name: String?, bundleId: String?)

    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let frontmostApp: FrontmostAppProvider

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var pausedUntil: Date = .distantPast

    /// Pasteboard type identifiers that indicate concealed / password-manager
    /// data; we never record items where any of these is present.
    private static let concealedTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("Pasteboard generator type"),
    ]

    init(
        pasteboard: NSPasteboard = .general,
        store: ClipboardStore,
        frontmostApp: @escaping FrontmostAppProvider = PasteboardMonitor.defaultFrontmostApp
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.frontmostApp = frontmostApp
    }

    /// Default provider: reads `NSWorkspace.shared.frontmostApplication`.
    static func defaultFrontmostApp() -> (name: String?, bundleId: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }

    /// Starts the polling timer on the main runloop. Idempotent.
    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.app.info("pasteboard monitor started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pause(until date: Date) {
        pausedUntil = date
    }

    /// Synchronous tick — invoked by the timer in production, and directly by
    /// tests to advance the monitor deterministically.
    func tickForTesting() { tick() }

    private func tick() {
        let current = pasteboard.changeCount
        defer { lastChangeCount = current }
        guard current != lastChangeCount else { return }
        guard Date() >= pausedUntil else {
            Log.app.debug("monitor paused, skipping change")
            return
        }
        captureCurrentContents()
    }

    private func captureCurrentContents() {
        // 1. Privacy: concealed types win immediately.
        if let types = pasteboard.types, !Set(types).isDisjoint(with: Self.concealedTypes) {
            Log.app.info("skipping concealed pasteboard item")
            return
        }

        // 2. Phase 2 scope: TEXT only. Detect non-text types and skip with a log.
        if pasteboard.types?.contains(.string) != true {
            if let t = pasteboard.types {
                Log.app.debug("non-text pasteboard ignored in Phase 2 (types=\(t.map(\.rawValue), privacy: .public))")
            }
            return
        }

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return
        }

        // 3. Capture.
        let (appName, bundleId) = frontmostApp()
        do {
            _ = try store.recordText(text, sourceApp: appName, sourceBundleId: bundleId)
        } catch {
            Log.app.error("store insert failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Services/PasteboardMonitor.swift ClipboardManagerTests/PasteboardMonitorTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "monitor: NSPasteboard polling with concealed + exclusion filters"
```

---

## Task 10: RetentionJob (TDD)

**Files:**
- Create: `ClipboardManager/Services/RetentionJob.swift`
- Create: `ClipboardManagerTests/RetentionTests.swift`

- [ ] **Step 1: Failing tests**

```swift
// ClipboardManagerTests/RetentionTests.swift
import XCTest
@testable import ClipboardManager

@MainActor
final class RetentionTests: XCTestCase {

    func testRunPurgesByAgeAndCount() throws {
        let store = try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
        // 200-day-old item.
        try store.testingInsertStaleItem(
            body: "ancient",
            createdAt: Int64(Date().timeIntervalSince1970) - 86_400 * 200
        )
        for i in 0..<25 {
            _ = try store.recordText("item-\(i)", sourceApp: nil, sourceBundleId: nil)
        }
        let job = RetentionJob(store: store, retentionDays: 90, maxItems: 10)
        try job.runOnce()
        let remaining = try store.recentItems(limit: 100)
        XCTAssertEqual(remaining.count, 10)
        XCTAssertFalse(remaining.map(\.body).contains("ancient"))
    }
}
```

- [ ] **Step 2: Run, verify fails**

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 3: Implement**

```swift
// ClipboardManager/Services/RetentionJob.swift
import Foundation

@MainActor
final class RetentionJob {

    private let store: ClipboardStore
    private let retentionDays: Int
    private let maxItems: Int

    private var timer: Timer?

    init(store: ClipboardStore, retentionDays: Int = 90, maxItems: Int = 5_000) {
        self.store = store
        self.retentionDays = retentionDays
        self.maxItems = maxItems
    }

    /// Starts a once-per-hour cleanup timer and runs an immediate pass.
    func start() {
        do { try runOnce() } catch { Log.app.error("retention initial pass: \(error.localizedDescription, privacy: .public)") }

        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                do { try self?.runOnce() } catch {
                    Log.app.error("retention pass: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One pass: age purge first, then count cap.
    func runOnce() throws {
        try store.purgeOlderThan(days: retentionDays)
        try store.purgeBeyondCount(max: maxItems)
    }
}
```

- [ ] **Step 4: Tests pass**

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Services/RetentionJob.swift ClipboardManagerTests/RetentionTests.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "retention: hourly purge by age + count cap"
```

---

## Task 11: ClipboardViewModel (drawer data source)

**Files:**
- Create: `ClipboardManager/ClipboardViewModel.swift`

A simple `@MainActor` `ObservableObject` that holds the current visible list. It is refreshed whenever the monitor records a change (we'll trigger via NotificationCenter).

- [ ] **Step 1: Add a notification name to ClipboardStore** so callers can re-fetch when something changes.

Edit `/Users/gal.lev/Clipboard/ClipboardManager/Store/ClipboardStore.swift`. At the bottom of the file (outside the class), add:

```swift

extension Notification.Name {
    /// Posted after any successful insert / delete / purge in ClipboardStore.
    /// Subscribers should re-query whatever slice they care about.
    static let clipboardStoreDidChange = Notification.Name("ClipboardStoreDidChange")
}
```

Then inside `ClipboardStore`, add a private helper `postChange()` and call it at the end of:
- `recordText` (only when an item was actually inserted or updated — i.e., not the early-return `nil` cases)
- `softDelete`
- `purgeOlderThan`
- `purgeBeyondCount`
- `addExclusion` (callers might want to refresh, though Phase 2 UI doesn't show exclusions yet — safe to include)
- `removeExclusion`

The helper:

```swift
    private func postChange() {
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
    }
```

In `recordText`, the early `return nil` paths must not post; both branches that produce a row must post. After the `return existing` in the dedupe branch, the wrapper returns from inside a `try queue.write { db in ... }`. Restructure so we post outside the write block:

```swift
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
            if var existing = try Item
                .filter(Item.Columns.contentHash == hash && Item.Columns.deletedAt == nil)
                .fetchOne(db)
            {
                existing.createdAt = now
                try existing.update(db)
                return existing
            }
            var item = Item(
                id: nil, kind: kindVal.kindColumn, subtype: kindVal.subtypeColumn,
                contentHash: hash, body: raw, blobPath: nil, dimensions: nil,
                byteSize: raw.utf8.count, sourceApp: sourceApp, sourceBundleId: sourceBundleId,
                createdAt: now, pinned: false, snippetId: nil, deletedAt: nil
            )
            try item.insert(db)
            return item
        }
        postChange()
        return result
    }
```

Similarly add `postChange()` after the write blocks of `softDelete`, `purgeOlderThan`, `purgeBeyondCount`, `addExclusion`, `removeExclusion`.

- [ ] **Step 2: Build + tests pass** (existing store tests should still pass; nothing observes the notification yet)

```bash
make test 2>&1 | tail -10
```

- [ ] **Step 3: Create the view model**

```swift
// ClipboardManager/ClipboardViewModel.swift
import Foundation
import Combine

@MainActor
final class ClipboardViewModel: ObservableObject {

    @Published private(set) var items: [Item] = []

    private let store: ClipboardStore
    private let visibleLimit: Int
    private var observer: NSObjectProtocol?

    init(store: ClipboardStore, visibleLimit: Int = 200) {
        self.store = store
        self.visibleLimit = visibleLimit
        observer = NotificationCenter.default.addObserver(
            forName: .clipboardStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func reload() {
        do {
            items = try store.recentItems(limit: visibleLimit)
        } catch {
            Log.app.error("view model reload failed: \(error.localizedDescription, privacy: .public)")
            items = []
        }
    }
}
```

- [ ] **Step 4: Build**

```bash
make build 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add ClipboardManager/Store/ClipboardStore.swift ClipboardManager/ClipboardViewModel.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "ui: ClipboardViewModel + store-did-change notification"
```

---

## Task 12: Minimal text ClipboardCard

Phase 2 ships text-only cards. Full multi-kind + hover preview + context menu is Phase 4.

**Files:**
- Create: `ClipboardManager/UI/Drawer/ClipboardCard.swift`

- [ ] **Step 1: Implement**

```swift
// ClipboardManager/UI/Drawer/ClipboardCard.swift
import SwiftUI

struct ClipboardCard: View {
    let item: Item
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var isCode: Bool {
        item.subtype == TextSubtype.code.rawValue || item.subtype == TextSubtype.json.rawValue
    }

    private var isURL: Bool {
        item.subtype == TextSubtype.url.rawValue
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .mask(LinearGradient(
                    stops: [.init(color: .black, location: 0.65),
                            .init(color: .clear, location: 1.0)],
                    startPoint: .top, endPoint: .bottom))

            // Footer
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 10, height: 10)
                Text(item.sourceApp ?? "Unknown")
                    .font(DesignTypography.cardFooterApp)
                    .foregroundStyle(.primary.opacity(dark ? 0.5 : 0.4))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(relativeTime(item.createdAt))
                    .font(DesignTypography.cardFooterTime)
                    .foregroundStyle(.primary.opacity(dark ? 0.3 : 0.25))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(DesignColors.hairline(dark: dark)),
                     alignment: .top)
        }
        .frame(width: 184, height: 210)
        .background(DesignColors.cardBackground(dark: dark))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var content: some View {
        if isCode {
            Text(item.body)
                .font(DesignTypography.cardCode)
                .foregroundStyle(.primary.opacity(dark ? 0.8 : 0.7))
        } else if isURL {
            Text(item.body)
                .font(DesignTypography.cardBody)
                .underline()
                .foregroundStyle(.primary.opacity(dark ? 0.8 : 0.7))
        } else {
            Text(item.body)
                .font(DesignTypography.cardBody)
                .foregroundStyle(.primary.opacity(dark ? 0.8 : 0.7))
        }
    }

    private func relativeTime(_ epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    let preview = Item(
        id: 1, kind: "text", subtype: "plain", contentHash: "abc",
        body: "Hello there, this is some text that wraps onto multiple lines so we can see the fade.",
        blobPath: nil, dimensions: nil, byteSize: 100,
        sourceApp: "Messages", sourceBundleId: "com.apple.MobileSMS",
        createdAt: Int64(Date().timeIntervalSince1970) - 120,
        pinned: false, snippetId: nil, deletedAt: nil
    )
    return ClipboardCard(item: preview)
        .padding()
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build**

```bash
make build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add ClipboardManager/UI/Drawer/ClipboardCard.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "ui: minimal text ClipboardCard (Phase 2 — text only)"
```

---

## Task 13: Wire DrawerView to the view model

**Files:**
- Modify: `ClipboardManager/UI/Drawer/DrawerView.swift`

- [ ] **Step 1: Replace the body** so the drawer renders the empty state when the list is empty, and a horizontal scroll of cards otherwise.

```swift
// ClipboardManager/UI/Drawer/DrawerView.swift
import SwiftUI

struct DrawerView: View {
    @ObservedObject var viewModel: ClipboardViewModel

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: DesignMaterials.drawer(dark: dark))

            LinearGradient(
                colors: dark
                    ? [Color(red: 52/255, green: 52/255, blue: 56/255).opacity(0.97),
                       Color(red: 32/255, green: 32/255, blue: 35/255).opacity(0.99)]
                    : [Color(red: 248/255, green: 248/255, blue: 252/255).opacity(0.97),
                       Color(red: 240/255, green: 240/255, blue: 245/255).opacity(0.99)],
                startPoint: .top,
                endPoint: .bottom
            )

            if viewModel.items.isEmpty {
                EmptyStateView()
            } else {
                cardStrip
            }
        }
        .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .stroke(DesignColors.hairline(dark: dark), lineWidth: 0.5)
        )
        .ignoresSafeArea()
    }

    private var cardStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.items, id: \.id) { item in
                    ClipboardCard(item: item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }
}

#Preview {
    let store = try! ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    let vm = ClipboardViewModel(store: store)
    return DrawerView(viewModel: vm)
        .frame(width: 1440, height: 300)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Update DrawerWindow.swift** to accept the view model and pass it through to DrawerView

Edit `/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/DrawerWindow.swift`. Change the initializer to accept a view model:

```swift
    init(viewModel: ClipboardViewModel) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // ... existing flag setup unchanged ...

        let host = NSHostingView(rootView: DrawerView(viewModel: viewModel))
        // ... rest unchanged ...
    }
```

(Leave all the property and method bodies alone except for changing the `NSHostingView(rootView: DrawerView())` line to pass the view model.)

- [ ] **Step 3: Update DrawerWindowController.swift** to accept and forward the view model

Edit `/Users/gal.lev/Clipboard/ClipboardManager/UI/Drawer/DrawerWindowController.swift`. Change `private let window = DrawerWindow()` to take a parameter, and add a constructor:

```swift
    private let window: DrawerWindow

    init(viewModel: ClipboardViewModel) {
        self.window = DrawerWindow(viewModel: viewModel)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDismissRequest),
            name: .drawerDismissRequested, object: nil
        )
    }
```

- [ ] **Step 4: Update AppCoordinator.swift** to construct the view model + store and wire it through

```swift
// ClipboardManager/App/AppCoordinator.swift
import AppKit

@MainActor
final class AppCoordinator {
    private let store: ClipboardStore
    private let viewModel: ClipboardViewModel
    private let menuBar: MenuBarController
    private let drawer: DrawerWindowController
    private let hotkey: HotkeyService
    private let monitor: PasteboardMonitor
    private let retention: RetentionJob

    init() throws {
        let store = try ClipboardStore()
        try store.seedDefaultExclusionsIfNeeded()
        self.store = store

        let viewModel = ClipboardViewModel(store: store)
        self.viewModel = viewModel

        let drawer = DrawerWindowController(viewModel: viewModel)
        self.drawer = drawer

        self.menuBar = MenuBarController { drawer.toggle() }
        self.hotkey = HotkeyService { drawer.toggle() }
        self.monitor = PasteboardMonitor(store: store)
        self.retention = RetentionJob(store: store)
    }

    func start() {
        Log.coordinator.info("coordinator starting")
        hotkey.start()
        monitor.start()
        retention.start()
    }
}
```

Note `init` now `throws` (because the store may fail to open). Update `AppDelegate.swift`:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("ClipboardManager launched (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
        NSApp.setActivationPolicy(.accessory)
        do {
            let coordinator = try AppCoordinator()
            coordinator.start()
            self.coordinator = coordinator
        } catch {
            Log.app.fault("failed to launch coordinator: \(error.localizedDescription, privacy: .public)")
            // Show an alert so the user knows something went wrong; the app
            // is otherwise dead-on-arrival because the DB couldn't open.
            let alert = NSAlert()
            alert.messageText = "Clipboard Manager couldn't start"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
```

- [ ] **Step 5: Build + tests pass**

```bash
make test 2>&1 | tail -10
```

Expected: all tests still pass (we changed APIs but tests construct components directly with their dependencies — verify by reading any failures and fixing them).

- [ ] **Step 6: Commit**

```bash
git add ClipboardManager/UI/Drawer/DrawerView.swift ClipboardManager/UI/Drawer/DrawerWindow.swift ClipboardManager/UI/Drawer/DrawerWindowController.swift ClipboardManager/App/AppCoordinator.swift ClipboardManager/App/AppDelegate.swift
git -c user.email="gal.lev@xmcyber.com" -c user.name="Gal Lev" commit -m "wire: drawer shows live clipboard items from store"
```

---

## Task 14: End-to-end smoke verification (manual)

No code changes. Verify Phase 2 in the running app.

- [ ] **Step 1: Rebuild and relaunch**

```bash
cd /Users/gal.lev/Clipboard
killall ClipboardManager 2>/dev/null; sleep 1
make build 2>&1 | tail -3
APP_DIR=$(xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/ {print $3; exit}')
open -g "$APP_DIR/ClipboardManager.app"
```

- [ ] **Step 2: Verify capture works**

  1. Copy some text in another app (e.g. select and ⌘C in a browser address bar).
  2. Press `⌘⇧V`.
  3. Expected: the copied text appears as a card.
  4. Copy another piece of text.
  5. Press `⌘⇧V` again.
  6. Expected: both items are now cards, newest leftmost.

- [ ] **Step 3: Verify dedupe**

  1. Copy the same string twice.
  2. Expected: only one card.

- [ ] **Step 4: Verify privacy**

  1. Quit and relaunch the app.
  2. Open 1Password (or Bitwarden), copy a credential.
  3. Open the drawer.
  4. Expected: no card for the credential.

- [ ] **Step 5: Verify persistence**

  1. Copy a few items.
  2. `killall ClipboardManager`.
  3. Relaunch (`open` the app bundle).
  4. Open drawer.
  5. Expected: previous items are still there.

- [ ] **Step 6: Tag Phase 2**

```bash
git tag -a v0.2.0-phase2 -m "Phase 2 complete: encrypted store + live pasteboard monitor + retention + privacy"
git log --oneline -10
```

---

## Phase 2 — Done criteria

- [ ] `make test` passes (all tests across both phases).
- [ ] Copying text in another app results in a card in the drawer within ~300 ms.
- [ ] Duplicates collapse (re-copy does not create a second row).
- [ ] Items from `com.agilebits.onepassword7`, `com.1password.1password8`, `com.bitwarden.desktop`, `com.apple.keychainaccess` are NOT recorded.
- [ ] Quit + relaunch keeps the items (DB at `~/Library/Application Support/Clipboard Manager/clipboard.sqlcipher`).
- [ ] `v0.2.0-phase2` tag exists.

## What's next (Phase 3 preview)

Image + file capture. Adds `BlobStore`, image rendering on cards (decimated thumbnails for the strip, full-resolution on hover later), file icon rendering, and file metadata extraction. The Phase 2 monitor's "non-text ignored" branch becomes a handler that classifies + writes blob + records.
