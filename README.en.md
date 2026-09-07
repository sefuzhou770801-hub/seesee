<p align="center">
  <img src="Resources/AppIcon-1024.png" width="144" height="144" alt="seesee app icon">
</p>

<h1 align="center">seesee</h1>

<p align="center">
  <a href="README.md">中文</a> · English · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  Paste a link, watch it offline. A macOS video player with bilingual subtitles built in.<br>
  Downloads the full video to your Mac and plays it in a clean native player, away from the noise of the web.
</p>

<p align="center">
  <a href="https://github.com/sefuzhou770801-hub/seesee/releases/latest"><strong>Download the latest release</strong></a>
  ·
  <a href="https://github.com/sefuzhou770801-hub/seesee/releases">All releases</a>
</p>

<p align="center">
  <img src="docs/images/seesee-banner.png" width="720" alt="seesee banner">
</p>

## The vision: a player that is an agent

seesee is not just trying to be a cleaner player. We believe the next generation of players is agentic: one that understands what you are watching and can talk about it with you.

- **Ask while watching (in private beta)**: press `a` at any moment to pause and ask a question; the answer draws on the current frame and the surrounding subtitles, and every exchange is pinned to the timeline so you can revisit it from the side pane. A chart you cannot parse, a term you did not catch, a claim you want to dig into: ask in place instead of switching away to search.
- **Coming next**: search across everything you have watched, automatic preview digests for freshly downloaded videos, watching trusted channels for you, skipping sponsor segments.

Learning from video should be a conversation, not a one-way stream.

## Install

1. Download the zip from the [releases page](https://github.com/sefuzhou770801-hub/seesee/releases/latest) and unzip it.
2. Drag **seesee.app** into your Applications folder.
3. This build is not notarized by Apple yet, so Control-click the app and choose **Open** the first time.

Apple Silicon (M-series) only, macOS 13 or newer. yt-dlp, ffmpeg, and Deno are bundled; no Homebrew required.

## Add something to watch

- Copy any text containing links, switch to seesee, and press **⌘V** to queue them all at once.
- Or paste into the field at the top of the queue, or drag a URL, `.webloc`, or `.url` file onto the window or Dock icon.

Videos download in the background and are stored locally for offline playback. YouTube and X are the primary targets; other non-DRM sites supported by yt-dlp may work too.

## Features

- **Play while downloading**: no need to wait for the download to finish; it automatically retries if the connection drops
- **Bilingual subtitles**: fetches Chinese and English subtitles automatically and shows the original and translation as a paired two-line caption, cycling through bilingual, translation-only, and off, remembered per video; external `.srt` / `.vtt` files named after the video file are picked up as well, with Chinese (`.zh.srt`) preferred as the translation track
- **Subtitle navigation pane**: full transcript grouped by sentence, click to jump, chapter sections, watched parts fold away
- **Resume everything**: position, speed, volume, subtitle mode, and pane state are saved per video
- **Queue management**: drag to reorder, rename in place, archive watched items, thumbnails, batch URL extraction
- **Playback comfort**: 10-second skips, full keyboard control, media keys, fullscreen, AirPlay, compact background player
- **Restraint**: nothing autoplays after a download or relaunch, and downloads pause in Low Power Mode

## Keyboard

| Key | Action |
| --- | --- |
| `⌘V` | Queue every URL on the clipboard |
| `Space` | Play or pause |
| `←` / `→` | Skip back or forward 10 seconds |
| `↑` / `↓` | Change speed by 0.1× |
| `F` | Toggle fullscreen |
| Vertical scroll over video | Adjust volume |

## AI key

Explain and Table of Contents call a language model, so they need an API key. Click the gear at the right end of the title bar (or **seesee › Settings…**, ⌘,), pick a provider and paste the key; it is verified automatically. It stays on this Mac, and subtitle excerpts are sent only when you ask for an explanation or a table of contents.

- Gemini: free key from [Google AI Studio](https://aistudio.google.com/apikey), no card required (recommended).
- Anthropic: key from the [Anthropic Console](https://console.anthropic.com/settings/keys), pay as you go.

The environment variables `GEMINI_API_KEY` and `ANTHROPIC_API_KEY` also work.

## Data and privacy

- Downloaded media: `~/Movies/Replay`
- Queue metadata: `~/Library/Application Support/Replay/queue.json`
- No analytics, no accounts, no cloud sync
- No browser cookie import
- No DRM decryption

Only download media you are authorized to watch and keep. Site terms and copyright rules still apply.

## Build from source

```sh
git clone https://github.com/sefuzhou770801-hub/seesee.git
cd seesee
./scripts/build_app.sh
./scripts/test.sh
```

The development build is written to `dist/Replay.app` and installed as `/Applications/seesee.app`. Set `REPLAY_INSTALL_APP=0` to build without installing, or `REPLAY_LAUNCH_APP=0` to install without launching. For local development the runtime tools come from Homebrew:

```sh
brew install yt-dlp ffmpeg deno
```

## Why Deno is bundled

YouTube gates requests behind JavaScript challenges that yt-dlp needs a restricted JavaScript runtime to solve, and Deno is its official recommendation. Deno is only invoked by yt-dlp while resolving videos and has nothing to do with the UI. A portable ffmpeg is bundled as well, for merging audio and video streams and converting thumbnails and subtitles. License notices for the runtime tools live inside the app under `Contents/Resources`.

## Acknowledgements

Built on top of [grinich/replay](https://github.com/grinich/replay); many thanks to the original author. On that foundation of an offline queue and native player, seesee adds a redesigned interface, bilingual subtitles, transcript navigation, play-while-downloading, and full Chinese localization.

## License

[MIT License](LICENSE). Bundled runtime components retain their respective upstream licenses.
