#!/usr/bin/env bash
# Build, sign, NOTARIZE, and package "CDT Usage.app" into a DMG that opens on any Mac with no Gatekeeper
# warnings (like an App Store / downloaded app) and can be re-opened from the Applications folder.
#
# Modes:
#   ./release.sh                 full notarized release (needs Developer ID + notary credentials)
#   ./release.sh --bundle-only   just build + bundle + sign (any cert) for local testing — no notarization
#   ./release.sh --publish       full release, then attach the DMG to a GitHub release
#
# ONE-TIME PREREQUISITES for a real (notarized) release — only you can set these up:
#   1) Paid Apple Developer Program membership ($99/yr) + a **Developer ID Application** certificate
#      in your login Keychain (developer.apple.com → Certificates). An "Apple Development" cert can't notarize.
#   2) Notary credentials saved once (app-specific password from appleid.apple.com):
#        xcrun notarytool store-credentials cdt-notary \
#          --apple-id "you@example.com" --team-id "XCANJ7SYKG" --password "abcd-efgh-ijkl-mnop"
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ONLY=0; PUBLISH=0
for a in "$@"; do case "$a" in --bundle-only) BUNDLE_ONLY=1 ;; --publish) PUBLISH=1 ;; esac; done

APP_NAME="CDT Usage"
NOTARY_PROFILE="${CDT_NOTARY_PROFILE:-cdt-notary}"
DIST="dist"; APP="$DIST/$APP_NAME.app"
VERSION="$(python3 -c "import json;print(json.load(open('../.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo 1.0.0)"

# --- signing identity ---
finder() { security find-identity -v -p codesigning 2>/dev/null | grep -m1 -E "$1" | sed -E 's/^.*"([^"]+)".*$/\1/' || true; }
if [ "$BUNDLE_ONLY" = 1 ]; then
  SIGN_ID="${CDT_SIGN_IDENTITY:-$(finder 'Developer ID Application')}"; [ -z "$SIGN_ID" ] && SIGN_ID="$(finder 'Apple Development|Developer ID')"
else
  SIGN_ID="${CDT_SIGN_IDENTITY:-$(finder 'Developer ID Application')}"
  if [ -z "$SIGN_ID" ]; then
    echo "❌ No 'Developer ID Application' certificate found — required to notarize."
    echo "   Get one: paid Apple Developer Program → developer.apple.com → Certificates → Developer ID Application."
    echo "   To just test the bundle locally with your current cert, run:  ./release.sh --bundle-only"
    exit 1
  fi
fi
echo "▶ Identity: ${SIGN_ID:-<none>}   Version: $VERSION"

# --- build + assemble .app ---
swift build -c release
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/cdt-menubar" "$APP/Contents/MacOS/cdt-menubar"
sed "s/__VERSION__/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"
[ -f "AppIcon.icns" ] && cp "AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# --- sign (hardened runtime + secure timestamp for a real release; plain for --bundle-only) ---
if [ -n "${SIGN_ID:-}" ]; then
  if [ "$BUNDLE_ONLY" = 0 ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP/Contents/MacOS/cdt-menubar"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
  else
    codesign --force --sign "$SIGN_ID" "$APP/Contents/MacOS/cdt-menubar"
    codesign --force --sign "$SIGN_ID" "$APP"
  fi
  codesign --verify --deep --strict "$APP" && echo "✓ Signed"
fi

if [ "$BUNDLE_ONLY" = 1 ]; then
  echo "✓ Bundle ready (not notarized): $APP"
  echo "  Test it:  open \"$APP\"   ·   then drag it to /Applications to keep it."
  exit 0
fi

# --- notarize → staple ---
ZIP="$DIST/$APP_NAME.zip"; ditto -c -k --keepParent "$APP" "$ZIP"
echo "▶ Submitting to Apple notary service…"
if ! xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
  echo "❌ Notarization failed. Save credentials first:"
  echo "   xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id XCANJ7SYKG --password <app-specific-pw>"
  exit 1
fi
xcrun stapler staple "$APP"; echo "✓ Notarized & stapled"

# --- DMG (drag-to-Applications) ---
STAGE="$DIST/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
DMG="$DIST/CDT-Usage-$VERSION.dmg"; rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "✓ DMG: $DMG"

if [ "$PUBLISH" = 1 ] && command -v gh >/dev/null 2>&1; then
  gh release create "v$VERSION" "$DMG" --title "v$VERSION" --notes "Notarized CDT Usage menu bar app." 2>/dev/null \
    || gh release upload "v$VERSION" "$DMG" --clobber
  echo "✓ Published to release v$VERSION"
fi
echo
echo "Done. Ship $DMG — users open it, drag 'CDT Usage' to Applications, run it with no warnings."
