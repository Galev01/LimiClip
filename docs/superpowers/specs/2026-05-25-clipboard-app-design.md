# Clipboard Manager — macOS App Design Spec

**Date:** 2026-05-25
**Status:** draft for review
**Visual reference (binding):** `design/mac-clipboard-app/project/Clipboard Manager.html` and its imported JSX files

## 1. Product summary

A premium, beautiful clipboard manager for macOS. Native SwiftUI + AppKit, menu-bar only (no Dock icon). Inspired visually by Paste.app with deeper power-user features: pinned snippets, keyword expansion, quick-action transforms, and full-text search across a rich, encrypted-at-rest history. Target: macOS 14 (Sonoma) and newer, Apple Silicon + Intel universal binary, Developer ID signed and notarized, distributed via GitHub Releases.

## 2. Scope (v1)

**In scope:**

1. Text clipboard history with subtype detection (plain / URL / code / JSON)
2. Image history with on-disk blob storage and inline thumbnails
3. File/path history (Finder file references)
4. Fuzzy substring search across all history with match highlighting
5. Snippets: pin any item, edit title and body, optional keyword expansion (e.g. `;sig` → email signature)
6. Quick actions on items: paste as plain text, copy-without-pasting, case transforms, encode/decode (Base64, URL, HTML), hashes (MD5/SHA1/SHA256), JSON pretty-print, trim whitespace, reveal in Finder, open URL, pin, delete
7. Global hotkey `⌘⇧V` opens the bottom drawer
8. Menu bar status item with dropdown (recent 5 + snippets + Preferences/Quit)
9. Bottom drawer UI per visual design — horizontal card strip, tabs, search, hover preview, context menu
10. Preferences window with five sections: General, Privacy, Snippets, Shortcuts, About
11. First-run onboarding flow (3 steps): welcome → Accessibility permission → hotkey
12. Empty state
13. Retention policy: defaults to 5,000 items / 90 days (user-configurable), auto-cleanup hourly. History Limit dropdown options: 500 / 1,000 / 5,000 / 10,000 / Unlimited. Retention options: 7 / 30 / 90 days / Forever.
14. Privacy: skip items with `org.nspasteboard.ConcealedType`, user-managed app exclusion list, "pause monitoring" quick action
15. Storage encrypted at rest via SQLCipher with key in Keychain

**Out of scope (deferred):**

- iCloud sync across Macs
- iOS companion
- Pinboards / collections (manual grouping beyond the Pinned tab)
- Auto-update via Sparkle (groundwork only; opt-in later)
- Mac App Store distribution (sandbox would restrict required permissions)

## 3. Architecture

```
ClipboardApp (NSApplication, .accessory policy — menu bar only)
│
├── AppCoordinator
│     ├── starts services on launch
│     ├── owns drawer window + preferences window
│     ├── handles permission flow + first-run onboarding
│     └── responds to global hotkey events
│
├── Services (singletons, dependency-injected)
│     ├── PasteboardMonitor      — polls NSPasteboard.changeCount @ ~250ms
│     ├── HotkeyService          — registers ⌘⇧V via CGEvent tap
│     ├── KeywordExpander        — kCGSessionEventTap monitors keystrokes
│     ├── PasteInjector          — synthesizes ⌘V into frontmost app
│     ├── PermissionsService     — Accessibility status + prompts
│     └── RetentionJob           — hourly cleanup loop
│
├── ClipboardStore (GRDB + SQLCipher)
│     ├── items table   (id, kind, subtype, hash, body, blob_path,
│     │                  source_app, source_bundle_id, created_at,
│     │                  pinned, snippet_id, deleted_at)
│     ├── snippets table (id, title, body, keyword, sort_order,
│     │                   created_at, updated_at)
│     ├── exclusions table (id, bundle_id, name)
│     └── blobs/  on-disk image storage (one file per blob)
│
├── ActionsKit (pure-function module — easy to unit test)
│     ├── Transform: upper/lower/title/camel/snake
│     ├── Encode/decode: Base64, URL, HTML entities
│     ├── Hash: MD5, SHA1, SHA256
│     ├── JSON pretty-print
│     ├── Trim whitespace
│     └── Subtype detection (url? code? json?)
│
└── UI (SwiftUI hosted via NSHostingView in custom NSWindows)
      ├── DrawerWindow        — borderless, screen-wide, bottom-anchored,
      │                         .statusBar level, .canJoinAllSpaces +
      │                         .fullScreenAuxiliary, NSVisualEffectView host
      ├── DrawerContent       — top bar (search/tabs/hint) + card strip
      ├── ClipboardCard       — 184×210, per-kind rendering
      ├── HoverPreview        — popover above card after 400ms
      ├── ContextMenu         — quick actions
      ├── MenuBarDropdown     — NSStatusItem with NSPopover SwiftUI content
      ├── PreferencesWindow   — 760×520, sidebar + content split
      ├── SnippetEditor       — modal sheet from Preferences
      ├── OnboardingFlow      — 3-step centered card window
      └── EmptyState          — drawer empty-history view
```

**External dependencies:**

- `GRDB.swift` (5.x or later) — SQLite wrapper
- `SQLCipher` — encryption at rest (linked via GRDB's `GRDB-SQLCipher` variant)
- `KeyboardShortcuts` (Sindre Sorhus) — global hotkey UX and customization
- `Sparkle` — auto-update framework (wired but opt-in)
- Everything else: system frameworks (AppKit, SwiftUI, Carbon for low-level hotkey, Security for Keychain, CryptoKit for hashing)

## 4. Data model

### `items` (clipboard history)

| Column            | Type     | Notes                                              |
|-------------------|----------|----------------------------------------------------|
| `id`              | INTEGER  | primary key, autoincrement                         |
| `kind`            | TEXT     | `text` \| `image` \| `file`                        |
| `subtype`         | TEXT     | `plain` \| `code` \| `json` \| `url` \| `screenshot` \| `photo` \| `design` \| null |
| `content_hash`    | TEXT     | SHA256 of canonical body — dedupe key              |
| `body`            | TEXT     | text content, or file path JSON, or null for image |
| `blob_path`       | TEXT     | relative path under blobs/ for images, null else   |
| `dimensions`      | TEXT     | `WxH` for images, null else                        |
| `byte_size`       | INTEGER  | content size for sorting/limits                    |
| `source_app`      | TEXT     | display name from frontmost app at copy time       |
| `source_bundle_id`| TEXT     | bundle id (for exclusion matching)                 |
| `created_at`      | INTEGER  | unix timestamp                                     |
| `pinned`          | INTEGER  | 0 \| 1 (item is a snippet if 1 and snippet_id set) |
| `snippet_id`      | INTEGER  | FK → snippets.id when pinned, else null            |
| `deleted_at`      | INTEGER  | soft delete for undo (purged after 24h)            |

Index on `(kind, created_at desc)`, `(content_hash)`, `(pinned, snippet_id)`.

Dedupe rule: if a new item's `content_hash` matches an existing non-deleted row, bump that row's `created_at` instead of inserting.

### `snippets`

| Column        | Type     | Notes                                  |
|---------------|----------|----------------------------------------|
| `id`          | INTEGER  | primary key                            |
| `title`       | TEXT     | display name (required)                |
| `body`        | TEXT     | snippet content (required)             |
| `keyword`     | TEXT     | optional, must match `^;[a-z0-9_-]+$`  |
| `sort_order`  | INTEGER  | manual ordering in Pinned tab          |
| `created_at`  | INTEGER  |                                        |
| `updated_at`  | INTEGER  |                                        |

Unique index on `keyword` where not null.

### `exclusions`

| Column       | Type    | Notes                            |
|--------------|---------|----------------------------------|
| `bundle_id`  | TEXT    | primary key — never recorded     |
| `name`       | TEXT    | display name                     |

Seeded with: `com.agilebits.onepassword7`, `com.1password.1password8`, `com.bitwarden.desktop`, `com.apple.keychainaccess`.

### `app_settings`

Single-row key/value table for user preferences (theme, hotkey, retention, pause-until timestamp, sound, etc.). Backed by `@AppStorage` mirrors in UI.

### Storage layout

```
~/Library/Application Support/Clipboard Manager/
  ├── clipboard.sqlcipher          (encrypted GRDB database)
  └── blobs/
        ├── 0f/1a/<uuid>.heic      (sharded by first 4 chars of uuid)
        └── ...
```

Encryption key: 256-bit random key generated on first launch, stored in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and label `com.gallev.clipboardmanager.db-key`.

## 5. Visual design — binding reference

The design bundle in `design/mac-clipboard-app/project/` is the source of truth for every visual decision. Specific anchor values that must be matched:

### Drawer container

- Height: 300 px (user-tunable 240–400)
- Pinned to bottom edge, full width of active display
- Corner radius: 16 px top-left and top-right only
- Background: `NSVisualEffectView` with material `.hudWindow` (dark) / `.popover` (light); we layer a 0.97-opacity gradient over it to ensure contrast on any wallpaper
- Border: 0.5 px hairline at `rgba(255,255,255,0.15)` dark / `rgba(0,0,0,0.08)` light
- Shadow: `0 -8px 60px rgba(0,0,0,0.5)` dark; `0 -8px 60px rgba(0,0,0,0.1)` light
- Entrance: slide-up via spring `response: 0.35, damping: 0.8` (mapped to `cubic-bezier(0.25,1,0.5,1)` curve in the prototype — we use SwiftUI `.spring(response: 0.35, dampingFraction: 0.8)`)
- Window level: `.statusBar`, `.canJoinAllSpaces`, `.fullScreenAuxiliary`, ignores activation

### Top bar (inside drawer)

- Padding: `14px 20px 10px`
- Three flex columns: search (left), tabs (center), keyboard hint (right)
- Search field: 28 px tall, collapsed width 32 px (icon only), expands to 220 px on `/` or click
- Tabs: pill segmented control, 5 tabs (All / Text / Images / Files / Pinned), active state = subtle inset background
- Hint: `⌘⇧V toggle` as kbd-styled tag

### Cards

- Size: 184 × 210 (width user-tunable 140–240)
- Radius: 12 px
- Gap: 12 px (user-tunable 6–20)
- Border: 0.5 px hairline; focused = 2 px solid system accent (default `#007AFF`)
- Hover: `transform: scale(1.03) translateY(-4px)` over 150 ms with shadow lift
- Footer: 8 px app-color dot + app name + relative time
- Content tints (subtle, in card body): text=transparent, image=blue, file=orange, snippet=purple

### Card content rendering

- **Text plain:** wrap, system font 12.5px/1.55, mask gradient bottom 35% so long text fades out
- **Text code / json:** SF Mono 11.5px/1.5, same mask
- **Text URL:** underlined, same mask
- **Image:** fills card with image (we use the actual image rendered at thumbnail size); dimension chip in bottom-right, white-on-black-blur
- **File:** centered file icon SVG (folded corner + extension badge in extension-colored rect) + filename below
- **Snippet:** extra header row inside card with title (left) + keyword badge in purple (right)

### Hover preview popover

- Appears after 400 ms hover
- Positioned above card, centered horizontally
- 340 px wide for text/file, 380 px wide for image
- Same vibrancy material + 0.5 px hairline
- Animation: fade + scale 0.96 → 1, 200 ms
- Pointer-events: none (dismissed on mouse-leave from card)

### Context menu (right-click / `⌘.`)

- Native NSMenu styled to match: `rgba(40,40,42,0.98)` dark, blur 50 px, blue selection
- Sections: Paste / Paste as Plain Text / Copy without Pasting · Transform ▸ / Encode/Decode ▸ / Pretty Print JSON / Trim Whitespace · Open URL (if URL) / Reveal in Finder (if file) / Pin to Snippets · Delete (red)
- Shortcuts shown on right side per item

### Menu bar dropdown (NSPopover)

- 280 px wide
- Section labels in tiny gray uppercase
- Recent (5 items, single-line truncated previews with app-color dot + relative time)
- Snippets (3 items with keyword badge)
- Open Clipboard… (`⌘⇧V`)
- Preferences… (`⌘,`)
- Quit Clipboard Manager (`⌘Q`)

### Preferences window

- 760 × 520 fixed size, rounded 14 px, traffic lights in sidebar top-left
- Sidebar: 200 px, 5 sections with colored letter-tile icons (General=blue, Privacy=orange, Snippets=purple, Shortcuts=green, About=gray)
- Sections per design — see Section 6 of this spec for per-screen requirements

### Snippet editor (sheet)

- 480 px wide, modal sheet over Preferences
- Fields: Title / Body (monospace, multi-line) / Keyword
- Live preview block at the bottom shows how the snippet renders
- Cancel + Save buttons; Save validates keyword regex

### Onboarding (3 steps)

- 420 px wide centered card on dim backdrop
- Step indicator dots, 80 px icon tile, 20 px bold title, 13 px body, optional "Why?" callout for permission step
- Buttons: Back (steps 2–3) + primary CTA (step-specific label)

### Empty state

- Centered ghost-clipboard icon at 0.2 opacity
- "Your clipboard is empty" + 12 px subtitle

### Dark/light mode

- Both modes specified throughout the design
- Follows macOS appearance by default; user can override in General preferences (System / Light / Dark)

## 6. Interaction details

### Activation

- Global `⌘⇧V` opens drawer with slide-up + fade
- Drawer floats over all spaces and full-screen apps
- Pressing `⌘⇧V` again toggles closed
- `Esc` dismisses

### Keyboard within drawer

- `←` / `→` move focus across cards (auto-scrolls into view)
- `⌘1` – `⌘9` jump to card N
- `Enter` pastes focused card into the previously-active app, then dismisses drawer
- `Shift+Enter` paste as plain text
- `⌘C` copy without pasting
- `⌘.` opens context menu on focused card
- `⌘S` pin focused card to snippets
- `⌘Delete` or `⌫` delete focused card (with 5-second undo toast)
- `/` focuses search
- `Tab` cycles tabs (All → Text → Images → Files → Pinned → All)

### Pasting

- After Enter, drawer dismisses → wait one runloop tick → write item to NSPasteboard → synthesize `⌘V` via CGEvent into frontmost app → restore previous clipboard contents after 1 s (so user's clipboard isn't polluted unless they want it to be)
- Configurable: "Replace clipboard with pasted item" toggle in General prefs (default off)

### Keyword expansion

- `KeywordExpander` runs a CGEventTap on `kCGSessionEventTap` watching `keyDown` events
- Maintains a rolling 32-char buffer of recently typed chars (reset on enter, escape, modifier-only sequences, or focus change via NSWorkspace notification)
- After each char, if buffer ends with any registered keyword, schedule expansion on next runloop:
  - Synthesize `Backspace` × `keyword.count`
  - Type out the snippet body via CGEvent unicode insertion
- Skip when frontmost app is in `passwordPaste`-disabled list or when caret context is a password field (heuristic: `AXSecureTextField` role via Accessibility API — best-effort)

### Privacy enforcement

- Each clipboard read checks `NSPasteboard.general.types` for `org.nspasteboard.ConcealedType` or `Pasteboard generator` provider — skip if present
- Each clipboard read inspects `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` and skips if in `exclusions` table
- "Pause Monitoring" sets a unix timestamp; monitor short-circuits while now < pause-until
- Password manager bundle IDs pre-seeded; can be removed by user

### Hover preview timing

- 400 ms hover delay before popover appears
- Popover dismissed on any mouse-leave or scroll, or 100 ms after cursor exits card

## 7. Permissions

| Permission        | When requested            | Purpose                                        |
|-------------------|---------------------------|------------------------------------------------|
| Accessibility     | Onboarding step 2         | Synthesize ⌘V keystroke + keystroke monitoring |
| Input Monitoring  | Same prompt (or step 2b)  | CGEventTap for keyword expansion              |
| (none for hotkey) | n/a                       | KeyboardShortcuts uses Carbon registration     |

If Accessibility is revoked at runtime, the app shows a non-blocking banner in the drawer and disables keyword expansion + paste injection (falls back to "copy to clipboard, user manually pastes").

## 8. Error handling

- DB open failure (corrupted / bad key): show recovery dialog → back up corrupt file, recreate fresh DB, log
- Blob write failure: drop the image, log, keep app running
- Pasteboard read failure for a given type: log, skip that item
- Hotkey registration conflict (another app owns it): show banner in preferences, allow user to pick a different one
- CGEventTap creation failure (Accessibility denied): degrade gracefully, banner in drawer
- All errors logged to `~/Library/Logs/Clipboard Manager/clipboard.log` via `os.Logger`

No silent retries, no "fall back to mock data" shortcuts.

## 9. Testing strategy

- **ActionsKit** — pure functions, full unit-test coverage (XCTest): every transform, encode/decode, hash, JSON detection, subtype detection
- **ClipboardStore** — XCTest hitting a temp-directory GRDB instance: insert, dedupe, retention, search, snippet CRUD, exclusions
- **PasteboardMonitor** — testable via injected pasteboard double; verify concealed-type skip, exclusion-app skip, pause-monitoring skip, dedupe
- **KeywordExpander** — unit-test the buffer/match logic in isolation; CGEventTap wiring is integration-tested manually
- **UI** — SwiftUI Preview-driven manual verification per screen; one XCUITest for the drawer open/close/paste happy path
- **Snapshot** — record drawer + preferences screens at light/dark, compare to the design's HTML render as the golden reference (manual visual diff, not automated pixel-diff)

## 10. Distribution & packaging

- Xcode project: `ClipboardManager.xcodeproj` (SPM for dependencies)
- Hardened Runtime enabled, Developer ID Application signing
- Notarization via `notarytool` in a `Makefile` target
- DMG built via `create-dmg` (Homebrew) with a styled background
- Sparkle appcast hosted at `https://gallev.dev/clipboard-manager/appcast.xml` (placeholder)
- GitHub Releases for binary hosting
- Universal binary (arm64 + x86_64), minimum macOS 14.0

## 11. Project layout

```
Clipboard/
├── ClipboardManager.xcodeproj
├── ClipboardManager/
│   ├── App/
│   │   ├── ClipboardManagerApp.swift
│   │   ├── AppCoordinator.swift
│   │   └── AppDelegate.swift
│   ├── Services/
│   │   ├── PasteboardMonitor.swift
│   │   ├── HotkeyService.swift
│   │   ├── KeywordExpander.swift
│   │   ├── PasteInjector.swift
│   │   ├── PermissionsService.swift
│   │   └── RetentionJob.swift
│   ├── Store/
│   │   ├── ClipboardStore.swift
│   │   ├── Item.swift
│   │   ├── Snippet.swift
│   │   ├── Exclusion.swift
│   │   ├── Migrations.swift
│   │   └── BlobStore.swift
│   ├── ActionsKit/
│   │   ├── Transforms.swift
│   │   ├── Encoders.swift
│   │   ├── Hashes.swift
│   │   ├── JSONPretty.swift
│   │   └── SubtypeDetector.swift
│   ├── UI/
│   │   ├── Drawer/
│   │   │   ├── DrawerWindow.swift
│   │   │   ├── DrawerView.swift
│   │   │   ├── TabBar.swift
│   │   │   ├── SearchField.swift
│   │   │   ├── ClipboardCard.swift
│   │   │   ├── HoverPreview.swift
│   │   │   └── ContextMenu.swift
│   │   ├── MenuBar/
│   │   │   └── MenuBarDropdown.swift
│   │   ├── Preferences/
│   │   │   ├── PreferencesWindow.swift
│   │   │   ├── GeneralPane.swift
│   │   │   ├── PrivacyPane.swift
│   │   │   ├── SnippetsPane.swift
│   │   │   ├── ShortcutsPane.swift
│   │   │   ├── AboutPane.swift
│   │   │   └── SnippetEditor.swift
│   │   ├── Onboarding/
│   │   │   └── OnboardingFlow.swift
│   │   ├── EmptyState.swift
│   │   └── DesignSystem/
│   │       ├── Colors.swift
│   │       ├── Materials.swift
│   │       └── Typography.swift
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   ├── Localizable.strings
│   │   └── Info.plist
│   └── Logging.swift
├── ClipboardManagerTests/
│   ├── ActionsKitTests.swift
│   ├── ClipboardStoreTests.swift
│   ├── PasteboardMonitorTests.swift
│   └── KeywordExpanderTests.swift
├── ClipboardManagerUITests/
│   └── DrawerSmokeTests.swift
├── design/                            (existing — visual reference)
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-05-25-clipboard-app-design.md   (this file)
└── Makefile                           (build, sign, notarize, dmg)
```

## 12. Implementation phasing (preview — full plan to come from writing-plans)

1. **Phase 1 — Scaffold.** Xcode project, SPM deps, AppDelegate as `.accessory`, menu bar status item, global hotkey, empty drawer window that opens/closes, design system tokens.
2. **Phase 2 — Pasteboard pipeline.** PasteboardMonitor + ClipboardStore + dedupe + retention + privacy enforcement. Drawer wired to live data with text items only.
3. **Phase 3 — Images and files.** Blob store, image rendering on cards, file icon rendering, subtype detection.
4. **Phase 4 — Drawer polish.** Hover preview, context menu, search, tabs, keyboard navigation, paste injection.
5. **Phase 5 — Snippets.** Pin flow, snippet CRUD, Pinned tab, snippet editor.
6. **Phase 6 — Keyword expansion.** CGEventTap, buffer logic, expansion synthesis.
7. **Phase 7 — Preferences window.** All five panes.
8. **Phase 8 — Onboarding + permissions UX.** First-run flow, permission status banners.
9. **Phase 9 — Quick actions inventory.** Wire every ActionsKit function into the context menu.
10. **Phase 10 — Distribution.** Signing, notarization, DMG, Sparkle wiring (disabled by default).

Each phase is independently shippable (the app remains runnable at the end of each phase), and produces meaningful UI you can use.

---

**Visual binding clause:** Anywhere this spec is ambiguous about look or feel, the design files in `design/mac-clipboard-app/project/` are authoritative. The implementation must visually match those mockups when rendered side-by-side in light and dark mode.
