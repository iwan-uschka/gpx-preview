#!/usr/bin/env bash
# Reset the Quick Look thumbnail cache so .gpx icons cached before the
# install are regenerated. Does not touch your files.
#
# Finder itself keeps icons in memory; pass --restart-finder to have this
# script restart it (it says so first), otherwise it only prints the hint.
set -euo pipefail

echo "Resetting Quick Look thumbnail cache…"
qlmanage -r cache >/dev/null || {
  echo "error: qlmanage -r cache failed; the thumbnail cache was NOT reset" >&2; exit 1; }
echo "✓ Cache reset."

case "${1:-}" in
  --restart-finder)
    echo "Restarting Finder (open Finder windows will close and reopen)…"
    killall Finder || {
      echo "error: killall Finder failed; Finder was NOT restarted (the cache reset above still happened)" >&2; exit 1; } ;;
  *)
    if [ -n "${1:-}" ]; then
      echo "warning: unrecognized argument '$1', ignoring" >&2
    fi
    echo "Finder may still show old icons from memory. To restart it:"
    echo "  killall Finder        (or rerun with --restart-finder)" ;;
esac
