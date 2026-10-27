#!/bin/zsh
# Takes the README screenshots of the live app into build/snapshots (dark and light) from demo files
# you pass in, using a scratch shelf store so your real shelves aren't touched. Ledge covers the screen
# with a plain backdrop (--stage) so nothing personal is in frame, and reports the rect to capture.
# Needs Screen Recording for your terminal. Pass --docs first to also copy the dark shots into docs/.
# Launches through `open` on purpose: running build/Ledge.app/Contents/MacOS/Ledge straight from a
# terminal makes macOS file Ledge's menu bar icon under the terminal app, and if that app is off in
# Settings > Menu Bar the icon disappears.
#
#   scripts/snapshots.sh [--docs] ~/Desktop/demo/*
set -euo pipefail
cd "${0:A:h}/.."
docs=0
if [[ "${1:-}" == "--docs" ]]; then docs=1; shift; fi
out=$PWD/build/snapshots
store=$(mktemp -d)
rect=$store/rect.txt
mkdir -p $out

shoot() {
  local name=$1; shift
  rm -f $rect
  open -n --env LEDGE_STORE=$store build/Ledge.app --args --stage --rect-out $rect "$@"
  for _ in {1..40}; do [[ -s $rect ]] && break; sleep 0.25; done
  sleep 0.5
  screencapture -x -R"$(cat $rect)" $out/$name.png
  pkill -f "$PWD/build/Ledge.app" || true
  sleep 1
}
for look in dark light; do
  shoot hero-$look --appearance $look --glow --shelf "${@:A}" --select
  shoot drop-$look --appearance $look --shelf "${@[1,2]:A}" --drop-target
  shoot empty-$look --appearance $look --shelf
  shoot settings-$look --appearance $look --settings
done
rm -rf $store
if (( docs )); then
  for name in hero drop settings; do cp $out/$name-dark.png docs/$name.png; done
fi
echo "Wrote $out"
