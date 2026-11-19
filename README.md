<p align="center"><img src="docs/design/app-icon/xsaves-icon.png" width="128" height="128" alt="xsaves icon: a floppy disk whose label is a bookmarked post"></p>

# xsaves

xsaves is a native SwiftUI app that archives your X bookmarks, likes, and their media on the Mac, and lets you search them and sort them into boards.

## Build

xsaves needs macOS 26 or later and the Swift 6.2 command line tools. Xcode isn't needed.

```sh
scripts/bundle.sh            # builds build/xsaves.app
scripts/bundle.sh --install  # also copies it to ~/Applications
swift test
```

## Use

Open xsaves and choose **Sync** (⌘R). A window for x.com appears only when you need to sign in. Turn on the six-hour background sync in Settings (⌘,).

The same binary works from the command line:

```sh
xsaves sync             # fetch new bookmarks and likes
xsaves schedule on|off  # install or remove the six-hour launchd agent
```

Saves, media, and the database live in `~/Library/Application Support/xsaves`. Set `XSAVES_DIR` to use another folder.

## Icon

The icon's source is [`docs/design/app-icon/xsaves-icon.svg`](docs/design/app-icon/xsaves-icon.svg). After editing it, run `scripts/icon.sh` to regenerate `Resources/AppIcon.icns` and the PNG copies used here and in the wiki.

## Docs

Decisions, open questions, and the SwiftUI implementation plan are in [`docs/wiki`](docs/wiki/index.md).
