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
