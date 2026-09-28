#!/usr/bin/env bash
# Remove "GPXPreview.app" from /Applications and unregister its extensions.
set -euo pipefail

DEST="/Applications/GPXPreview.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

killall "GPXPreview" GPXQuickLook GPXThumbnail >/dev/null 2>&1 || true
if [ -d "$DEST" ]; then
  pluginkit -r "$DEST/Contents/PlugIns/GPXQuickLook.appex" >/dev/null 2>&1 || true
  pluginkit -r "$DEST/Contents/PlugIns/GPXThumbnail.appex" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$DEST" >/dev/null 2>&1 || true
  rm -rf "$DEST"
  echo "✓ Removed $DEST"
else
  echo "note: $DEST not found; nothing to remove."
fi
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

# PluginKit drops registrations asynchronously; report anything left over.
for id in io.github.iwan-uschka.GPXPreview.QuickLook io.github.iwan-uschka.GPXPreview.Thumbnail; do
  out="$(pluginkit -m -i "$id" 2>/dev/null || true)"
  if [ -n "$out" ] && [ "$out" != "(no matches)" ]; then
    echo "⚠️  $id still listed by pluginkit (another copy on disk, or not yet dropped):"
    pluginkit -m -v -i "$id" 2>/dev/null | sed 's/^/    /' || true
  fi
done
