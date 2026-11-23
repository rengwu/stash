#!/bin/sh
# Builds Resources/AppIcon.icns and the PNG copies used by the README and wiki
# from docs/design/app-icon/kaleidostash-icon.svg.
# Run it again whenever the SVG changes, then commit the new files.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -O -o "$tmp/render-icon" scripts/render-icon.swift
set="$tmp/AppIcon.iconset"
mkdir "$set"
for size in 16 32 128 256 512; do
  "$tmp/render-icon" docs/design/app-icon/kaleidostash-icon.svg "$set/icon_${size}x${size}.png" "$size"
  "$tmp/render-icon" docs/design/app-icon/kaleidostash-icon.svg "$set/icon_${size}x${size}@2x.png" "$((size * 2))"
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
cp "$set/icon_256x256@2x.png" docs/design/app-icon/kaleidostash-icon.png
cp "$set/icon_128x128.png" docs/wiki/attachments/app-icon/icon-128.png
echo Resources/AppIcon.icns docs/design/app-icon/kaleidostash-icon.png docs/wiki/attachments/app-icon/icon-128.png
