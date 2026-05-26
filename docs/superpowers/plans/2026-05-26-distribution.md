# Distribution & Notarization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a repeatable one-command build + sign + notarize + DMG pipeline so LimiClip can be distributed to other Macs.

**Architecture:** Shell script wraps xcodebuild archive → export → notarytool → stapler → hdiutil. ExportOptions.plist configures Developer ID signing. DISTRIBUTION.md documents prerequisites (Developer ID cert, app-specific password).

**Tech Stack:** xcodebuild, xcrun notarytool, xcrun stapler, hdiutil, bash

---

## File Map

| Path | Action | Purpose |
|------|--------|---------|
| `scripts/ExportOptions.plist` | Create | Tells `xcodebuild -exportArchive` to use Developer ID signing |
| `scripts/build-release.sh` | Create | Full pipeline: archive → export → notarize → staple → DMG |
| `DISTRIBUTION.md` | Create | Prerequisites guide and one-command usage instructions |

---

## Background: current code-signing state

`project.yml` sets `CODE_SIGN_IDENTITY: "2F56B4673CCAA3BA84E2B5517710EEDF1A04112E"` — that SHA identifies an **Apple Development** certificate (personal dev cert). This cert is only trusted on machines enrolled in the same developer account. Distributing the `.app` directly will trigger Gatekeeper on every other Mac.

Distribution requires a **Developer ID Application** certificate, which is issued from *Certificates, Identifiers & Profiles* on developer.apple.com. The scripts below override `CODE_SIGN_IDENTITY` at archive time; `project.yml` does **not** need to change for local development.

---

## Task 1: ExportOptions.plist

**Files:**
- Create: `scripts/ExportOptions.plist`

- [ ] **Step 1: Create the `scripts/` directory**

```bash
mkdir -p /Users/gal.lev/Clipboard/scripts
```

- [ ] **Step 2: Create `scripts/ExportOptions.plist`**

Create the file with this exact content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>U2KLSZAS5J</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>hardened-runtime</key>
    <true/>
</dict>
</plist>
```

Key notes:
- `method: developer-id` — produces a `.app` signed for distribution outside the Mac App Store.
- `signingStyle: manual` — consistent with the Manual style already set in `project.yml`; prevents Xcode from auto-selecting a cert and picking the wrong one.
- `signingCertificate: Developer ID Application` — matches the certificate *name prefix* in Keychain. The full cert name will be `Developer ID Application: Gal Lev (U2KLSZAS5J)` once created.
- `hardened-runtime: true` — **required** for notarization; the runtime restriction is already set in `project.yml` (`ENABLE_HARDENED_RUNTIME: YES`), but explicitly repeating it here guarantees the exported binary keeps it.

- [ ] **Step 3: Verify the plist is valid**

```bash
plutil -lint /Users/gal.lev/Clipboard/scripts/ExportOptions.plist
```

Expected output:
```
/Users/gal.lev/Clipboard/scripts/ExportOptions.plist: OK
```

- [ ] **Step 4: Commit**

```bash
cd /Users/gal.lev/Clipboard
git add scripts/ExportOptions.plist
git commit -m "dist: add ExportOptions.plist for Developer ID export"
```

---

## Task 2: build-release.sh

**Files:**
- Create: `scripts/build-release.sh`

- [ ] **Step 1: Create `scripts/build-release.sh`**

Create the file with this exact content:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SCHEME="ClipboardManager"
BUNDLE_ID="dev.gallev.ClipboardManager"
TEAM_ID="U2KLSZAS5J"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Read MARKETING_VERSION from xcodebuild build settings
VERSION=$(xcodebuild \
    -project "$REPO_ROOT/ClipboardManager.xcodeproj" \
    -scheme "$SCHEME" \
    -showBuildSettings 2>/dev/null \
    | awk '/MARKETING_VERSION/ { print $3; exit }')

if [[ -z "$VERSION" ]]; then
    echo "❌  Could not read MARKETING_VERSION from build settings."
    exit 1
fi

ARCHIVE_PATH="$REPO_ROOT/build/LimiClip.xcarchive"
EXPORT_PATH="$REPO_ROOT/build/LimiClip-export"
APP_PATH="$EXPORT_PATH/ClipboardManager.app"
DMG_PATH="$REPO_ROOT/build/LimiClip-${VERSION}.dmg"

# ── Apple ID credentials (set as env vars before running) ────────────────────
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"   # app-specific password from appleid.apple.com

if [[ -z "$APPLE_ID" || -z "$APPLE_APP_PASSWORD" ]]; then
    echo "❌  Set APPLE_ID and APPLE_APP_PASSWORD before running."
    echo ""
    echo "    export APPLE_ID=you@example.com"
    echo "    export APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx"
    echo ""
    echo "    Create an app-specific password at: https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
    exit 1
fi

# ── Preflight: verify Developer ID cert is installed ──────────────────────────
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "❌  No 'Developer ID Application' certificate found in Keychain."
    echo "    See DISTRIBUTION.md → Prerequisites for how to create and install one."
    exit 1
fi

# ── 1. Archive ─────────────────────────────────────────────────────────────────
echo "📦  Archiving $SCHEME v${VERSION}…"
xcodebuild archive \
    -project "$REPO_ROOT/ClipboardManager.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    2>&1 | grep -E "^(error:|warning:|Build |Archive )"

echo "✓  Archive: $ARCHIVE_PATH"

# ── 2. Export ──────────────────────────────────────────────────────────────────
echo "📤  Exporting for Developer ID…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_PATH"

echo "✓  Export: $APP_PATH"

# ── 3. Notarize ────────────────────────────────────────────────────────────────
echo "🔏  Submitting for notarization (this may take 1-5 minutes)…"
xcrun notarytool submit "$APP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait \
    --output-format json

echo "✓  Notarization accepted."

# ── 4. Staple ──────────────────────────────────────────────────────────────────
echo "📎  Stapling notarization ticket…"
xcrun stapler staple "$APP_PATH"
echo "✓  Stapled."

# ── 5. Create DMG ─────────────────────────────────────────────────────────────
echo "💿  Creating DMG: $DMG_PATH"
# Remove any previous DMG at the same path so hdiutil -ov works cleanly
rm -f "$DMG_PATH"
hdiutil create \
    -volname "LimiClip ${VERSION}" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo ""
echo "✅  Done: $DMG_PATH"
echo "    Distribute this file to other Macs."
echo ""
echo "    Verify with Gatekeeper:"
echo "    spctl -a -vvv \"$APP_PATH\""
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x /Users/gal.lev/Clipboard/scripts/build-release.sh
```

- [ ] **Step 3: Verify bash syntax**

```bash
bash -n /Users/gal.lev/Clipboard/scripts/build-release.sh && echo "Syntax OK"
```

Expected output:
```
Syntax OK
```

- [ ] **Step 4: Verify the preflight cert-check logic works (dry run without the cert)**

Temporarily unset APPLE_ID and APPLE_APP_PASSWORD to confirm the credential guard fires:

```bash
cd /Users/gal.lev/Clipboard
APPLE_ID="" APPLE_APP_PASSWORD="" bash scripts/build-release.sh 2>&1 | head -5
```

Expected output (lines may vary slightly):
```
❌  Set APPLE_ID and APPLE_APP_PASSWORD before running.
```

- [ ] **Step 5: Commit**

```bash
cd /Users/gal.lev/Clipboard
git add scripts/build-release.sh
git commit -m "dist: add build-release.sh — archive, notarize, staple, DMG pipeline"
```

---

## Task 3: DISTRIBUTION.md

**Files:**
- Create: `DISTRIBUTION.md` (repo root)

- [ ] **Step 1: Create `DISTRIBUTION.md`**

Create the file with this exact content:

```markdown
# Distributing LimiClip to Other Macs

This guide explains how to build a notarized, Gatekeeper-friendly DMG of LimiClip
that can be handed to any Mac user running macOS 14 Sonoma or later.

---

## Prerequisites

Complete every item before running the release script.

### 1. Apple Developer Program membership

You must be enrolled in the Apple Developer Program ($99/year).
Check at: https://developer.apple.com/account/

### 2. Developer ID Application certificate

The project currently uses an **Apple Development** certificate
(`2F56B4673CCAA3BA84E2B5517710EEDF1A04112E`), which only works for local testing.
Distribution requires a separate **Developer ID Application** certificate.

**How to create one:**

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Click the **+** button.
3. Under "Software", select **Developer ID Application** → Continue.
4. Follow the prompts to generate a Certificate Signing Request (CSR) from Keychain
   Access (Keychain Access → Certificate Assistant → Request a Certificate from a
   Certificate Authority → save to disk).
5. Upload the CSR, download the resulting `.cer` file.
6. Double-click the `.cer` file — it installs into your login Keychain automatically.

**Verify installation:**

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Expected output (name will include your legal name):
```
  1) ABCDEF1234...  "Developer ID Application: Gal Lev (U2KLSZAS5J)"
```

### 3. App-specific password

Apple's notarization service requires an app-specific password (not your Apple ID
login password).

1. Go to https://appleid.apple.com → Sign-In and Security → App-Specific Passwords.
2. Click **+**, give it a label like `LimiClip notarytool`.
3. Copy the generated `xxxx-xxxx-xxxx-xxxx` password — you will not see it again.

### 4. Xcode Command Line Tools

```bash
xcode-select --install
```

If already installed, this prints:
```
xcode-select: error: command line tools are already installed
```

---

## One-Command Release Build

```bash
export APPLE_ID=you@example.com
export APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx

./scripts/build-release.sh
```

The script will:

| Step | Tool | Output |
|------|------|--------|
| 1 | `xcodebuild archive` | `build/LimiClip.xcarchive` |
| 2 | `xcodebuild -exportArchive` | `build/LimiClip-export/ClipboardManager.app` |
| 3 | `xcrun notarytool submit --wait` | Notarization accepted by Apple |
| 4 | `xcrun stapler staple` | Ticket embedded in `.app` bundle |
| 5 | `hdiutil create` | `build/LimiClip-<version>.dmg` |

The final `LimiClip-<version>.dmg` is safe to distribute. Double-clicking it on any
Mac will mount a volume containing `ClipboardManager.app` ready to drag to
`/Applications`.

---

## Current cert vs. distribution cert

| Certificate type | Who signed | Where trusted |
|-----------------|------------|---------------|
| Apple Development (`2F56B4673CCAA3BA84E2B5517710EEDF1A04112E`) | Personal dev cert | Only Macs in the same developer account |
| Developer ID Application | Apple-countersigned | **All** Macs via Gatekeeper |

The `project.yml` `CODE_SIGN_IDENTITY` value is **not changed** by this pipeline.
The release script overrides the identity at archive time only, so your normal
`make build` / `make test` workflow continues to use the development cert.

---

## Verifying Gatekeeper acceptance

After the script finishes, confirm Gatekeeper accepts the app:

```bash
spctl -a -vvv build/LimiClip-export/ClipboardManager.app
```

Expected output:
```
build/LimiClip-export/ClipboardManager.app: accepted
source=Notarized Developer ID
```

If you see `rejected` or `source=no usable signature`, the notarization step failed
or the wrong cert was used. Re-run the script after verifying the Developer ID
Application cert is installed.

---

## Troubleshooting

### `error: No signing certificate "Developer ID Application" found`

The Developer ID Application cert is not in your Keychain.
Follow the steps in **Prerequisites → 2** above.

### `notarytool` exits with `Invalid credentials`

The app-specific password is wrong or expired.
Generate a new one at https://appleid.apple.com and re-export `APPLE_APP_PASSWORD`.

### `notarytool` exits with status `Invalid` (notarization rejected)

Apple rejected the submission — usually because of a hardened runtime issue or a
disallowed entitlement.

Check the detailed log:

```bash
xcrun notarytool log <submission-id> \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id U2KLSZAS5J
```

The submission ID is printed in the JSON output of the `notarytool submit` step.

### Notarization takes longer than 15 minutes

Apple's service is occasionally slow. The `--wait` flag keeps the process running.
If it times out, use:

```bash
xcrun notarytool wait <submission-id> \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id U2KLSZAS5J
```

Then re-run only the staple + DMG steps manually:

```bash
xcrun stapler staple build/LimiClip-export/ClipboardManager.app
hdiutil create \
    -volname "LimiClip 0.1.0" \
    -srcfolder build/LimiClip-export/ClipboardManager.app \
    -ov -format UDZO \
    build/LimiClip-0.1.0.dmg
```
```

- [ ] **Step 2: Verify the markdown renders without errors**

```bash
# Quick check: no broken fenced code blocks (odd number of ``` markers = broken)
grep -c '```' /Users/gal.lev/Clipboard/DISTRIBUTION.md
```

The count should be an **even** number (each opening fence has a closing one).
Current expected count: `22` (11 pairs).

- [ ] **Step 3: Commit**

```bash
cd /Users/gal.lev/Clipboard
git add DISTRIBUTION.md
git commit -m "dist: add DISTRIBUTION.md — prerequisites, one-command usage, troubleshooting"
```

---

## Self-Review

### Spec coverage check

| Spec requirement | Covered by |
|-----------------|-----------|
| `ExportOptions.plist` with correct keys | Task 1 |
| `build-release.sh` — archive step | Task 2 |
| `build-release.sh` — export step | Task 2 |
| `build-release.sh` — notarize with `notarytool` | Task 2 |
| `build-release.sh` — wait + staple | Task 2 |
| `build-release.sh` — DMG via `hdiutil` | Task 2 |
| `DISTRIBUTION.md` — prereqs (Developer ID cert, app-specific password, CLT) | Task 3 |
| `DISTRIBUTION.md` — how to get Developer ID cert | Task 3 |
| `DISTRIBUTION.md` — how to create app-specific password | Task 3 |
| `DISTRIBUTION.md` — one-command usage | Task 3 |
| `DISTRIBUTION.md` — current cert vs Developer ID note | Task 3 |
| Gatekeeper verification (`spctl`) | Task 3 |
| `chmod +x` on script | Task 2, Step 2 |
| Graceful failure when cert not installed | Task 2, Step 1 (preflight block) |

No gaps found.

### Placeholder scan

No "TBD", "TODO", "fill in", "similar to", or "add appropriate" phrases present. All code blocks contain complete, copy-paste-ready content.

### Type/name consistency

- Script variable `APP_PATH` resolves to `$EXPORT_PATH/ClipboardManager.app` — consistent with `ClipboardManager.xcodeproj` scheme name throughout.
- `SCHEME` is `ClipboardManager` everywhere — matches `project.yml`.
- `TEAM_ID` is `U2KLSZAS5J` everywhere — matches spec and `project.yml`.
- `BUNDLE_ID` is `dev.gallev.ClipboardManager` — matches `project.yml`.
- `ExportOptions.plist` path referenced in script as `"$SCRIPT_DIR/ExportOptions.plist"` — correct relative to `scripts/` where both files live.
