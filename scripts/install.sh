#!/usr/bin/env bash
# Install the built "GPX Preview.app" to /Applications and register its
# Quick Look preview and thumbnail extensions. Reverse with uninstall.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Release/GPX Preview.app"
DEST="/Applications/GPX Preview.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[ -d "$APP" ] || { echo "error: not built yet. Run: scripts/build.sh" >&2; exit 1; }
codesign --verify --deep --strict "$APP" || {
  echo "error: signature invalid at $APP; rebuild with scripts/build.sh" >&2; exit 1; }

echo "── Quitting any running copy ──"
osascript -e 'quit app "GPX Preview"' >/dev/null 2>&1 || true
killall "GPX Preview" GPXQuickLook GPXThumbnail >/dev/null 2>&1 || true
# Forget the build-tree copy so the system can't pick its extensions instead.
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true

echo "── Copying to $DEST ──"
rm -rf "$DEST"
ditto "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "── Registering ──"
"$LSREGISTER" -f -R -trusted "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/GPXQuickLook.appex"
pluginkit -a "$DEST/Contents/PlugIns/GPXThumbnail.appex"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo
echo "✓ Installed $DEST"
echo
echo "Verify:"
echo "  pluginkit -mAvvv -p com.apple.quicklook.preview   | grep -A3 GPX"
echo "  pluginkit -mAvvv -p com.apple.quicklook.thumbnail | grep -A3 GPX"
echo "  swift -e 'import UniformTypeIdentifiers; print(UTType(filenameExtension:\"gpx\")!.identifier)'"
echo "  mdls -name kMDItemContentType Tests/Fixtures/full-1.1.gpx"
echo "  qlmanage -p Tests/Fixtures/full-1.1.gpx"
echo "  qlmanage -t -s 512 -o /tmp/qlout Tests/Fixtures/full-1.1.gpx"
echo
echo "If Finder shows no preview, enable it under System Settings → General →"
echo "Login Items & Extensions → Quick Look, and open the app once (Gatekeeper"
echo "may ask for \"Open Anyway\" in Privacy & Security)."
