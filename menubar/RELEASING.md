# Releasing a notarized "CDT Usage.app"

The menu bar app ships two ways:
1. **Build-from-source** (default) — the plugin auto-builds + signs it locally on macOS; nothing is downloaded.
2. **Notarized DMG** (this doc) — a downloadable, signed + **notarized** `.app` that opens on any Mac with
   **no Gatekeeper warnings** and re-opens from /Applications, like an App Store app.

> **Important:** notarization needs a **Developer ID Application** certificate.
> An **Apple Distribution** cert (App Store) or **Apple Development** cert will **not** work — and this app
> *can't* go on the Mac App Store anyway, because it reads Claude Code's Keychain item and calls an internal
> endpoint, both of which App Store sandboxing blocks. So Developer ID + notarization is the only path.

## One-time setup · Team ID `XCANJ7SYKG`

1. **Create a Developer ID Application certificate** (you already have a paid Apple Developer account):
   - **Xcode → Settings → Accounts →** your team **→ Manage Certificates → "+" → Developer ID Application**
   - (or developer.apple.com → Certificates, IDs & Profiles → "+" → *Developer ID Application*)
   - Verify: `security find-identity -v -p codesigning` now lists a **"Developer ID Application"** line.

2. **Create an app-specific password:** appleid.apple.com → Sign-In and Security → **App-Specific Passwords**.

3. **Store the notary credentials once:**
   ```bash
   xcrun notarytool store-credentials cdt-notary \
     --apple-id "YOUR_APPLE_ID_EMAIL" \
     --team-id "XCANJ7SYKG" \
     --password "xxxx-xxxx-xxxx-xxxx"
   ```

## Cut a release
```bash
cd menubar
./release.sh             # build → sign (Developer ID + hardened runtime) → notarize → staple → DMG
./release.sh --publish   # same, then attach the DMG to a GitHub release (needs gh)
```
Output: `menubar/dist/CDT-Usage-<version>.dmg`. Users open it, drag **CDT Usage** to Applications, run it
— no warnings, re-openable from /Applications.

> **Version source:** `release.sh` reads `<version>` from `../.claude-plugin/plugin.json` (it also fills
> the app's `Info.plist` `__VERSION__`). Bump `plugin.json` **before** cutting a release, and tag/publish
> the matching `v<version>` — otherwise the DMG name and the GitHub release tag can drift.

## Test the bundle without notarizing (works with any cert)
```bash
./release.sh --bundle-only      # builds + signs the .app; then:  open "dist/CDT Usage.app"
```
