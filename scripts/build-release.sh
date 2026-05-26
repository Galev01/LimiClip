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
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"

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
