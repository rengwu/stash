#!/bin/sh
# Builds build/xsaves.app from the Swift package. With --install, copies it to ~/Applications.
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product xsaves
app=build/xsaves.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/xsaves "$app/Contents/MacOS/xsaves"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/xsaves.app"
  cp -R "$app" "$HOME/Applications/xsaves.app"
fi
echo "$app"
