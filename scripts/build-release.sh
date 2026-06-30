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
APP_PATH="$EXPORT_PATH/LimiClip.app"
ZIP_PATH="$REPO_ROOT/build/LimiClip-${VERSION}.zip"
DMG_PATH="$REPO_ROOT/build/LimiClip-${VERSION}.dmg"

# ── Apple notarization credentials ───────────────────────────────────────────
# Prefer a stored notarytool keychain profile (NOTARY_PROFILE) so the secret
# never lives in env vars or CI logs; fall back to APPLE_ID + APPLE_APP_PASSWORD.
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"

if [[ -z "$NOTARY_PROFILE" && ( -z "$APPLE_ID" || -z "$APPLE_APP_PASSWORD" ) ]]; then
    echo "❌  Provide notarization credentials, one of:"
    echo ""
    echo "    # Option A — stored keychain profile (recommended):"
    echo "    xcrun notarytool store-credentials \"limiclip-notary\" --apple-id you@example.com --team-id $TEAM_ID"
    echo "    export NOTARY_PROFILE=limiclip-notary"
    echo ""
    echo "    # Option B — env vars:"
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

# ── 3. Zip for notarization (notarytool requires .zip, .pkg, or .dmg) ─────────
echo "🗜  Zipping app for notarization…"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ── 4. Notarize ────────────────────────────────────────────────────────────────
echo "🔏  Submitting for notarization (this may take 1-5 minutes)…"
if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --output-format json
else
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait \
        --output-format json
fi

echo "✓  Notarization accepted."

# ── 5. Staple ──────────────────────────────────────────────────────────────────
echo "📎  Stapling notarization ticket…"
xcrun stapler staple "$APP_PATH"
echo "✓  Stapled."

# ── 6. Create the drag-to-Applications DMG ────────────────────────────────────
echo "💿  Creating DMG: $DMG_PATH"
DMG_STAGING="$REPO_ROOT/build/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
rm -f "$DMG_PATH"

# Preferred: a styled window with the app on the left and an Applications
# drop-target on the right (the familiar "drag to install" layout). Falls back
# to a plain DMG if create-dmg isn't available or its Finder styling fails
# (e.g. a headless build with no Finder automation).
if command -v create-dmg >/dev/null 2>&1 && \
   create-dmg \
       --volname "LimiClip ${VERSION}" \
       --window-pos 200 120 \
       --window-size 560 380 \
       --icon-size 128 \
       --icon "LimiClip.app" 150 200 \
       --hide-extension "LimiClip.app" \
       --app-drop-link 410 200 \
       --no-internet-enable \
       "$DMG_PATH" "$DMG_STAGING"; then
    echo "✓  Styled drag-to-Applications DMG."
else
    echo "⚠️  create-dmg unavailable or failed — building a plain DMG instead."
    rm -f "$DMG_PATH"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create \
        -volname "LimiClip ${VERSION}" \
        -srcfolder "$DMG_STAGING" \
        -ov \
        -format UDZO \
        "$DMG_PATH"
fi

rm -rf "$DMG_STAGING"

# ── 7. Sign + notarize + staple the DMG container itself ──────────────────────
# The app inside is already notarized+stapled; doing the DMG too means the
# downloaded .dmg passes Gatekeeper cleanly on first mount, even offline.
echo "🔏  Signing the DMG…"
codesign --force --timestamp --sign "Developer ID Application" "$DMG_PATH"

echo "🔏  Notarizing the DMG…"
if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json
else
    xcrun notarytool submit "$DMG_PATH" --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$TEAM_ID" --wait --output-format json
fi

echo "📎  Stapling the DMG…"
xcrun stapler staple "$DMG_PATH"
echo "✓  DMG signed, notarized, stapled."

# ── 8. Sparkle: sign the update + (re)generate the appcast ────────────────────
# Produces build/appcast.xml with an EdDSA signature over the DMG. Sparkle
# verifies that signature (SUPublicEDKey) before installing. Requires the
# one-time bootstrap (run `generate_keys` once; the private key lives in the
# login Keychain). Skipped automatically until that bootstrap is done.
PUBKEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")
if [[ -z "$PUBKEY" || "$PUBKEY" == "REPLACE_WITH_GENERATED_ED25519_PUBLIC_KEY" ]]; then
    echo "⚠️  Skipping Sparkle appcast — SUPublicEDKey not configured yet."
    echo "    One-time bootstrap: run Sparkle's generate_keys, paste the public"
    echo "    key into ClipboardManager/Info.plist (SUPublicEDKey), then re-release."
else
    # Locate Sparkle's CLI tools from the resolved SPM artifacts.
    DD=$(xcodebuild -project "$REPO_ROOT/ClipboardManager.xcodeproj" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | awk '/ BUILD_DIR =/ { print $3; exit }')
    SPARKLE_BIN=$(find "${DD%/Build/*}" "$HOME/Library/Developer/Xcode/DerivedData" -path "*artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)
    if [[ -z "$SPARKLE_BIN" || ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
        echo "❌  Sparkle tools (generate_appcast) not found. Resolve packages first:"
        echo "    xcodebuild -resolvePackageDependencies -scheme $SCHEME"
        exit 1
    fi
    echo "🔏  Generating appcast (Sparkle tools: $SPARKLE_BIN)…"
    # Enclosure URLs MUST be versioned (not /latest/) so the download always
    # matches its appcast entry; only the SUFeedURL uses /latest/.
    "$SPARKLE_BIN/generate_appcast" \
        --download-url-prefix "https://github.com/Galev01/LimiClip/releases/download/v${VERSION}/" \
        -o "$REPO_ROOT/build/appcast.xml" \
        "$REPO_ROOT/build"
    echo "✓  Appcast: $REPO_ROOT/build/appcast.xml"
    echo ""
    echo "    Publish BOTH the DMG and the appcast on the release, e.g.:"
    echo "    gh release create v${VERSION} \"$DMG_PATH\" \"$REPO_ROOT/build/appcast.xml\" --title \"LimiClip ${VERSION}\""
fi

echo ""
echo "✅  Done: $DMG_PATH"
echo "    Distribute this file to other Macs."
echo ""
echo "    Gatekeeper check (must say 'accepted / Notarized Developer ID'):"
echo "    spctl -a -vvv \"$APP_PATH\""
echo "    spctl -a -t open --context context:primary-signature -vvv \"$DMG_PATH\""
echo ""
echo "    Publish this SHA-256 in the release notes:"
shasum -a 256 "$DMG_PATH"
