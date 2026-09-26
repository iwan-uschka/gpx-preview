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

if [ "${1:-}" = "--restart-finder" ]; then
  echo "Restarting Finder (open Finder windows will close and reopen)…"
  killall Finder
else
  echo "Finder may still show old icons from memory. To restart it:"
  echo "  killall Finder        (or rerun with --restart-finder)"
fi
