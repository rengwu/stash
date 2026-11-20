# stash

<img src="docs/design/app-icon/stash-icon.png" alt="stash icon: a floppy disk whose label is a bookmarked post" width="34%" align="right">

stash is a native SwiftUI app that archives your X bookmarks, likes, and their media on the Mac, and lets you search them and sort them into boards.

[Download for macOS](https://github.com/rengwu/stash/releases/latest/download/stash.zip)

<br clear="right">

## Install

Unzip `stash.zip`, move **stash.app** into **Applications**, and open it. Requires macOS 26 or later on Apple Silicon or Intel.

The release uses an ad-hoc signature and ships without Apple notarization. If macOS blocks the first launch, choose **Open Anyway** in **System Settings → Privacy & Security**.

## Build

stash needs macOS 26 or later and the Swift 6.2 command line tools. Xcode isn't needed.

```sh
scripts/bundle.sh            # builds build/stash.app
scripts/bundle.sh --install  # also copies it to ~/Applications
scripts/bundle.sh --release  # packages the universal app as build/stash.zip
swift test
```

## Use

Open stash and choose **Sync** (⌘R). A window for x.com appears only when you need to sign in. Turn on the six-hour background sync in Settings (⌘,).

Run the bundled executable from the command line. If you installed with `scripts/bundle.sh --install`, use `~/Applications` in these paths.

```sh
/Applications/stash.app/Contents/MacOS/stash sync
/Applications/stash.app/Contents/MacOS/stash schedule on  # use off to remove the agent
```

New archives live in `~/Library/Application Support/stash`. Set `STASH_DIR` to use another folder.

If you used Mosaic or xsaves, stash opens your existing archive in place and reuses your X sign-in. It also recognizes `MOSAIC_DIR`, `XSAVES_DIR`, and existing sync schedules. To point your schedule at the installed stash app, run the `schedule on` command above.

## Icon

The icon's source is [`docs/design/app-icon/stash-icon.svg`](docs/design/app-icon/stash-icon.svg). After editing it, run `scripts/icon.sh` to regenerate `Resources/AppIcon.icns` and the PNG copies used here and in the wiki.

## Docs

Decisions, open questions, and the SwiftUI implementation plan are in [`docs/wiki`](docs/wiki/index.md).
