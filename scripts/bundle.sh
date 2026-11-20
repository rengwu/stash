#!/bin/sh
# Builds build/stash.app from the Swift package. With --install, copies it to ~/Applications.
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product stash
app=build/stash.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/stash "$app/Contents/MacOS/stash"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/stash.app"
  cp -R "$app" "$HOME/Applications/stash.app"
fi
echo "$app"
