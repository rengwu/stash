#!/bin/sh
# Builds a local app, installs it with --install, or packages a universal ZIP with --release.
set -eu
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--release" ]; then
  mkdir -p build
  staging=$(mktemp -d build/.stash-release.XXXXXX)
  trap 'rm -rf "$staging"' EXIT
  # Separate builds also work with the Command Line Tools alone.
  for arch in arm64 x86_64; do
    swift build -c release --product stash --arch "$arch"
    bin_dir=$(swift build -c release --arch "$arch" --show-bin-path)
    cp "$bin_dir/stash" "$staging/$arch"
  done
  executable="$staging/stash"
  lipo -create "$staging/arm64" "$staging/x86_64" -output "$executable"
else
  swift build -c release --product stash
  executable="$(swift build -c release --show-bin-path)/stash"
fi
app=build/stash.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$executable" "$app/Contents/MacOS/stash"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
codesign --verify --deep --strict --all-architectures "$app"
if [ "${1:-}" = "--release" ]; then
  ditto -c -k --norsrc --noextattr --keepParent "$app" "$staging/stash.zip"
  mv "$staging/stash.zip" build/stash.zip
  echo build/stash.zip
fi
if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/stash.app"
  cp -R "$app" "$HOME/Applications/stash.app"
fi
echo "$app"
