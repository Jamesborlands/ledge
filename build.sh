#!/bin/zsh
# Builds Ledge.app into build/. Pass --install to copy it to /Applications and relaunch it.
set -euo pipefail
cd "${0:A:h}"

mkdir -p build
swiftc -O -swift-version 5 -target arm64-apple-macosx26.0 -sdk "$(xcrun --show-sdk-path)" \
  Sources/Ledge/*.swift -o build/Ledge

if [[ ! -f Resources/AppIcon.icns ]]; then
  iconset=build/AppIcon.iconset
  rm -rf $iconset && mkdir -p $iconset
  swiftc scripts/make_icon.swift -o build/make_icon && build/make_icon build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out $iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out $iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $iconset -o Resources/AppIcon.icns
fi

app=build/Ledge.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
cp build/Ledge $app/Contents/MacOS/Ledge
cp Resources/Info.plist $app/Contents/Info.plist
cp Resources/AppIcon.icns $app/Contents/Resources/AppIcon.icns
codesign --force --sign - $app
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Ledge 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Ledge.app
  cp -R $app /Applications/Ledge.app
  open /Applications/Ledge.app
  echo "Installed to /Applications/Ledge.app"
fi
