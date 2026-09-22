# Contributing

Thanks for helping improve Replay.

## Local setup

Replay requires macOS 13 or newer and Swift 5.9 or newer.

```sh
git clone https://github.com/grinich/replay.git
cd replay
./scripts/build_app.sh
./scripts/test.sh
```

Development builds use `yt-dlp`, `ffmpeg`, and optionally `deno` from the app bundle first, then fall back to Homebrew locations. Install local copies with:

```sh
brew install yt-dlp ffmpeg deno
```

`build_app.sh` installs the finished app at `/Applications/Replay.app` and launches it by default. Use `REPLAY_INSTALL_APP=0` for a build-only run or `REPLAY_LAUNCH_APP=0` to install without launching.

## Pull requests

- Keep changes focused and explain the user-visible behavior.
- Run `swift build -c release` and `./scripts/test.sh` before opening a pull request.
- Do not commit downloaded media, app bundles, or files from `.build`.

## Releases

The version comes from `Resources/Info.plist`. To publish a release, update both bundle version fields, then build a signed and notarized archive locally:

```bash
REPLAY_SIGNING_IDENTITY="Developer ID Application: YIQI XIE (ANVS3UQK9W)" \
REPLAY_NOTARIZE=1 REPLAY_NOTARY_PROFILE=openmy-notary \
REPLAY_UNIVERSAL=0 REPLAY_BUNDLED_TOOLS_DIR=.build/runtime-tools/arm64 \
    ./scripts/package_release.sh
```

The script signs every bundled executable with the hardened runtime and a secure timestamp (Deno keeps its own Developer ID signature), submits the app for notarization, staples the ticket, and writes `dist/release-v<version>/seesee-v<version>-apple-silicon.zip` plus its SHA-256 checksum. Push a matching `v*` tag and attach both files to the GitHub release. Never publish an archive whose notarization was not accepted.
