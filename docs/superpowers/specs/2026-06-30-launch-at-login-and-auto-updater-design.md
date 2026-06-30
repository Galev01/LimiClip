# Launch-at-Login Persistence Fix + Sparkle Auto-Updater — Design

**Date:** 2026-06-30
**Status:** Approved (design), pending implementation
**Branch context:** `cycle1-stability` (LimiClip 0.6.2)

## Summary

Two interlocking changes:

1. **Bug fix** — "Launch at Login" does not reliably stick across restarts / app
   updates. Root-caused below.
2. **Feature** — In-app auto-updater (one-click download + verify + install +
   relaunch) backed by Sparkle, fed from GitHub Releases.

They interlock: an auto-updater *replaces the app bundle*, which is precisely
when a fragile login-item registration is lost. The launch-at-login fix's
startup-reconciliation step is what keeps the login item sticky across the
updates the new feature performs.

---

## Issue #1 — Launch-at-login persistence

### Root cause (investigated, not guessed)

The `SMAppService` registration mechanism works (BTM dump confirmed
`/Applications/LimiClip.app` as `enabled, allowed`). The defects are in the
surrounding handling:

1. **`.requiresApproval` is silently swallowed.** `LaunchAtLogin.setEnabled(true)`
   calls `SMAppService.mainApp.register()`. On first registration macOS returns
   status `.requiresApproval` (user must approve in System Settings → General →
   Login Items) and **`register()` does not throw**. `GeneralPane` then runs
   `launchAtLogin = LaunchAtLogin.isEnabled`, where `isEnabled` is
   `status == .enabled` → `false` for `.requiresApproval`. The toggle silently
   flips back OFF, the user is never told to approve, and the app does not launch
   at login. This is the reported symptom.
2. **Intent is never persisted.** `Settings.Key.launchAtLogin` is declared
   (commented "tracked-only; service mgmt is source of truth") but is **dead
   code** — nothing reads or writes it. There is no record of "user wants this on."
3. **No startup reconciliation.** `register()` is only ever called from the
   toggle's `onChange`. Nothing re-asserts registration at launch, so if macOS
   drops it (app moved/updated, e.g. by the new auto-updater, or the
   DerivedData-vs-`/Applications` trap) nothing re-registers it.

### Design

**`LaunchAtLogin` helper (`ClipboardManager/Settings.swift`)** — make it
status-aware instead of `Bool`-only:

- Expose the real `SMAppService.Status` via a computed `status` property.
- Keep `isEnabled` (`status == .enabled`) for read sites that only care about the
  binary truth.
- `setEnabled(_:)` returns a small result enum so callers can react to approval:

  ```swift
  enum LoginItemOutcome { case enabled, requiresApproval, disabled }
  ```

  On `true`: `register()`, then inspect status. If `.requiresApproval`, call
  `SMAppService.openSystemSettingsLoginItems()` and return `.requiresApproval`.
- Persist user intent: `setEnabled(_:)` writes the desired bool to
  `Settings.Key.launchAtLogin` (wiring up the dead key as the intent record).

**Startup reconciliation** — a pure, unit-testable decision function plus a thin
caller invoked from `AppDelegate.applicationDidFinishLaunching`:

```swift
enum LaunchAtLoginReconciler {
    enum Action { case none, register, needsApproval }
    static func action(intent: Bool, status: SMAppService.Status) -> Action {
        guard intent else { return .none }            // user doesn't want it on
        switch status {
        case .enabled:         return .none           // already good
        case .notRegistered, .notFound: return .register
        case .requiresApproval: return .needsApproval
        @unknown default:      return .none
        }
    }
}
```

The caller maps `.register` → `LaunchAtLogin.setEnabled(true)` and `.needsApproval`
→ (log; the toggle UI surfaces the hint when the user next opens Preferences).
Reconciliation runs once at launch and is cheap.

**`GeneralPane` toggle (`UI/Preferences/GeneralPane.swift`)** — reflect true
status:

- When `setEnabled(true)` returns `.requiresApproval`, keep the toggle ON
  (intent) and show a hint row: "Approve LimiClip in System Settings → Login
  Items" with a button that calls `openSystemSettingsLoginItems()`. Do **not**
  silently revert to OFF.
- On `.disabled`/`.enabled`, behave as today.

### Tests

`ClipboardManagerTests` — unit-test `LaunchAtLoginReconciler.action(intent:status:)`
across the full matrix of intents × statuses. This is a pure function, so no real
`SMAppService` is touched. The UI and the helper's `register()` call are verified
manually.

---

## Issue #2 — Sparkle auto-updater

### Decision: Sparkle (vs. custom GitHub-API updater)

One-click in-app install requires a secure download → verify → atomic replace →
relaunch sequence. That is the part most likely to be subtly wrong in a
hand-rolled updater, and this app is security-conscious (encryption, notarization).
Sparkle is the well-audited standard for non-MAS Mac apps, works with the
existing notarized `.dmg`, and (app is **not sandboxed** —
`com.apple.security.app-sandbox = false`) integrates without the XPC-service
complexity sandboxed apps require. Custom approach rejected: more security-critical
code to own and test for no real benefit.

### Architecture

**Dependency:** add Sparkle via Swift Package Manager to
`ClipboardManager.xcodeproj` (package product `Sparkle`, linked to the
`ClipboardManager` target).

**`UpdaterController`** (new file, e.g. `ClipboardManager/Services/UpdaterController.swift`)
— thin wrapper around Sparkle's `SPUStandardUpdaterController`:

- Instantiated and started during app launch (owned by `AppCoordinator` /
  `AppDelegate`).
- `startingUpdater: true`, automatic checks enabled.
- Exposes `checkForUpdates()` for the manual menu item, and `canCheckForUpdates`
  for enabling/disabling that item.

**UI surface (menu-bar / LSUIElement app):**

- A **"Check for Updates…"** item in the existing menu-bar menu, wired to
  `UpdaterController.checkForUpdates()`.
- An **"Updates"** section in `GeneralPane`: an "Automatically check for updates"
  toggle (bound to the updater's `automaticallyChecksForUpdates`), a "Check Now"
  button, and a current-version label (`CFBundleShortVersionString`).

Sparkle's standard update dialog (version, release notes, Install button) and
progress UI come for free and work for accessory/agent apps.

**Info.plist keys (`ClipboardManager/Info.plist`):**

| Key | Value |
|-----|-------|
| `SUFeedURL` | `https://github.com/Galev01/LimiClip/releases/latest/download/appcast.xml` |
| `SUPublicEDKey` | `<EdDSA public key>` (generated once, see bootstrap) |
| `SUEnableAutomaticChecks` | `YES` |

The feed URL uses the `releases/latest/download/<asset>` redirect so it always
resolves to the newest release's `appcast.xml`.

### Security model

Sparkle verifies, before installing, **both**:

1. the **EdDSA signature** on the downloaded DMG (from `SUPublicEDKey`), and
2. Apple **code-signing + notarization** of the contained app.

The EdDSA private key never enters the repo (stored in macOS Keychain on the
release machine); only the public key ships in Info.plist.

### Data flow

```
launch → UpdaterController starts → Sparkle polls SUFeedURL (appcast.xml)
      → newer version in feed? → show update dialog (notes from feed)
      → user clicks Install → download DMG from release asset URL
      → verify EdDSA sig + notarization → mount → replace bundle → relaunch
      → AppDelegate startup reconciliation re-registers login item if intent==on
```

---

## Issue #2b — Release pipeline changes

Extends `scripts/build-release.sh`. After today's step 7 (DMG signed, notarized,
stapled), add:

8. **Sign the update:** `sign_update build/LimiClip-<VERSION>.dmg` (Sparkle tool)
   → emits the `sparkle:edSignature` and `length`.
9. **Generate/append `appcast.xml`:** run Sparkle's `generate_appcast` against the
   folder of released DMGs (it reads the signed DMG, version, min-macOS, and
   embedded release notes) to (re)produce `build/appcast.xml`.
10. **Publish:** `gh release create v<VERSION> build/LimiClip-<VERSION>.dmg
    build/appcast.xml ...` so `releases/latest/download/appcast.xml` resolves to
    the newest feed.

### One-time bootstrap (first Sparkle-aware release)

Sparkle can only update *from* a build that already contains Sparkle. The first
rollout therefore requires:

1. `generate_keys` → create the EdDSA keypair; store the private key in Keychain,
   put the public key in Info.plist (`SUPublicEDKey`).
2. Ship the first Sparkle-aware build (a new tag, e.g. **v0.6.3**) with the
   updater integrated and the first `appcast.xml` published as a release asset.
3. From v0.6.3 onward, every release follows the pipeline above and updates flow
   automatically.

These bootstrap secrets (EdDSA private key location, `generate_keys`/`sign_update`
usage) should be documented in the release runbook (`release-and-install` memory /
DISTRIBUTION.md), not committed.

---

## Out of scope (YAGNI)

- Delta updates.
- Beta/staged rollout channels.
- Hosting the appcast anywhere other than GitHub release assets.
- Migrating the legacy DerivedData login item (covered by startup reconciliation
  pointing at the running bundle).

## Testing summary

- **Launch-at-login:** unit tests on `LaunchAtLoginReconciler.action`.
- **Updater:** Sparkle is the tested component; verify our wrapper wiring + an
  end-to-end manual update (test appcast → higher version → one-click → relaunch),
  including a bad-signature rejection.
- **Interlock:** after a Sparkle update replaces the bundle, confirm startup
  reconciliation re-registers the login item when intent was on.
