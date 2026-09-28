#!/usr/bin/env bash
# Build "GPXPreview.app" (host + Quick Look preview + thumbnail extensions)
# and ad-hoc sign it. No paid Apple developer account needed.
#
# Usage: scripts/build.sh [x.y.z]
#   Version: the argument if given, else the first released "## [x.y.z]"
#   heading in CHANGELOG.md, else 0.0.0 for dev builds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ $# -gt 0 ]; then
  V="$1"
else
  V="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md 2>/dev/null | head -1 | tr -d '#[] ' || true)"
  V="${V:-0.0.0}"
fi
if ! [[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must be MAJOR.MINOR.PATCH (got '$V')" >&2
  exit 1
fi

command -v xcodegen >/dev/null 2>&1 || {
  echo "error: xcodegen not found. Install with: brew install xcodegen" >&2; exit 1; }
xcodebuild -version >/dev/null 2>&1 || {
  echo "error: full Xcode required (xcode-select -p → $(xcode-select -p 2>/dev/null))" >&2; exit 1; }

echo "── Generating Xcode project ──"
xcodegen generate

echo "── Building Release, version $V ──"
xcodebuild \
  -project GPXPreview.xcodeproj \
  -scheme GPXPreview \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  MARKETING_VERSION="$V" \
  CURRENT_PROJECT_VERSION="$V" \
  build | { if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)' || true; fi; }

APP="build/DerivedData/Build/Products/Release/GPXPreview.app"
QL="$APP/Contents/PlugIns/GPXQuickLook.appex"
TH="$APP/Contents/PlugIns/GPXThumbnail.appex"
for bundle in "$APP" "$QL" "$TH"; do
  [ -d "$bundle" ] || { echo "error: build produced no $bundle" >&2; exit 1; }
done

# The built extension plists must still carry the NSExtension block exactly as
# written in the sources; registration silently fails without it.
check_extension_plist() {
  local built="$1" source="$2"
  diff <(/usr/libexec/PlistBuddy -x -c "Print :NSExtension" "$built/Contents/Info.plist") \
       <(/usr/libexec/PlistBuddy -x -c "Print :NSExtension" "$source") >/dev/null || {
    echo "error: NSExtension in $built differs from $source" >&2; exit 1; }
}
check_extension_plist "$QL" Sources/QuickLook/Info.plist
check_extension_plist "$TH" Sources/Thumbnail/Info.plist

echo "── Ad-hoc signing, inside out ──"
sign() { codesign --force --sign - --timestamp=none --options runtime "$@"; }
sign --entitlements Sources/QuickLook/QuickLook.entitlements "$QL"
sign --entitlements Sources/Thumbnail/Thumbnail.entitlements "$TH"
sign --entitlements Sources/Host/Host.entitlements "$APP"

echo "── Verifying ──"
codesign --verify --deep --strict --verbose=2 "$APP" || {
  echo "error: signature invalid for $APP" >&2; exit 1; }
# No bundle may ever gain network access: both extensions draw from the file
# alone, and the host app only shows install guidance. A failure to read the
# entitlements aborts too, so the check can never pass without having run.
for bundle in "$QL" "$TH" "$APP"; do
  ents="$(codesign -d --entitlements - --xml "$bundle" 2>&1)" || {
    echo "error: could not read entitlements for $(basename "$bundle")" >&2; exit 1; }
  if grep -q 'com.apple.security.network' <<<"$ents"; then
    echo "error: $(basename "$bundle") carries a network entitlement" >&2; exit 1
  fi
done

echo
echo "✓ Built $APP ($V)"
echo "  Install with: scripts/install.sh"
