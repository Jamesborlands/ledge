#!/bin/zsh
# Renders the raw README screenshots into build/snapshots from demo files you pass in, using a
# scratch shelf store so your real shelves aren't touched. Launches through `open` on purpose:
# running build/Ledge.app/Contents/MacOS/Ledge straight from a terminal makes macOS file Ledge's
# menu bar icon under the terminal app, and if that app is off in Settings > Menu Bar the icon
# disappears.
#
#   scripts/snapshots.sh ~/Desktop/demo/*
set -euo pipefail
cd "${0:A:h}/.."
out=$PWD/build/snapshots
store=$(mktemp -d)
mkdir -p $out

snap() {
  open -n --env LEDGE_STORE=$store build/Ledge.app --args "$@"
  sleep 5
  pkill -f "$PWD/build/Ledge.app" || true
  sleep 1
}
snap --shelf "${@:A}" --snapshot $out/shelf.png
snap --shelf "${@[1,2]:A}" --drop-target --snapshot $out/drop.png
snap --settings-snapshot $out/settings.png
snap --glow-snapshot $out/glow.png --flare
rm -rf $store
echo "Wrote $out"
