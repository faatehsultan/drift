<p align="center">
  <img src="Resources/brand/logo-1024.png" width="148" alt="Drift app icon">
</p>

<h1 align="center">Drift</h1>

<p align="center">
  <b>Your notch, finally useful.</b><br>
  A free, open-source control center that lives in your MacBook's notch:<br>
  music with synced lyrics, media from any app, a file tray, calendar, focus timer and AI agent approvals.
</p>

<p align="center">
  <a href="https://github.com/faatehsultan/drift/releases/latest"><img src="https://img.shields.io/github/v/release/faatehsultan/drift?label=download&color=8b6cff" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple" alt="macOS 13+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/faatehsultan/drift?color=4fe3ff" alt="License: GPL-3.0"></a>
  <a href="https://github.com/faatehsultan/drift/actions/workflows/build.yml"><img src="https://github.com/faatehsultan/drift/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <a href="https://github.com/faatehsultan/drift/stargazers"><img src="https://img.shields.io/github/stars/faatehsultan/drift?style=flat&color=ff5fa8" alt="Stars"></a>
</p>

<p align="center">
  <a href="https://faatehsultan.github.io/drift/"><b>Website</b></a> ·
  <a href="https://github.com/faatehsultan/drift/releases/latest/download/Drift.dmg"><b>Download</b></a> ·
  <a href="#build-from-source">Build from source</a> ·
  <a href="CONTRIBUTING.md">Contribute</a>
</p>

<!-- Add a demo GIF here: docs/screenshots/demo.gif -->

---

## What it does

Point at the top of your screen and Drift springs out of the notch. Move away and it tucks itself back in.

| | |
|---|---|
| 🎵 **Music** | A native YouTube Music player: search, albums, artists, queue, likes, and colors that follow the album art. |
| 💬 **Synced lyrics** | Lines highlight and scroll with the song. Tap a line to jump to it. |
| 🌐 **Any app** | Music or video playing in Chrome, Safari, Arc, Spotify or Apple Music shows up too, with play, pause, skip and seek. Drift's own player always takes priority, and only one thing plays at a time. |
| 📥 **File tray** | Drag files onto the notch to park them. AirDrop them, merge PDFs, or convert images, PDFs, video and documents. |
| 📅 **Calendar** | Your next meeting with a live countdown and a one-click Join for Zoom, Meet, Teams and Webex. |
| ⏱️ **Focus tools** | Timer and Pomodoro (counting down in the notch), notes, to-dos, Shortcuts, clipboard history and a camera mirror. |
| ✨ **AI approvals** | Claude Code permission requests pop up in the notch with Allow and Deny. |
| 🏝️ **Live activities** | Now playing, timers, meetings, charging and new files show around the camera, like the Dynamic Island. |
| 🎨 **Make it yours** | Liquid Glass or solid black. Show, hide and reorder every section, widget, tool and live activity. |

Works on Macs without a notch too: a slim pill takes its place.

## Install

**Easiest:** paste this in Terminal. It downloads the latest Drift, installs it and opens it, with no Gatekeeper warning ([read the script](docs/install.sh)):

```sh
curl -fsSL https://faatehsultan.github.io/drift/install.sh | bash
```

**Or download it:**

1. Get **[Drift.dmg](https://github.com/faatehsultan/drift/releases/latest/download/Drift.dmg)** and drag Drift into Applications.
2. Open it. macOS will say **"Drift Not Opened"** because Drift isn't signed with Apple's paid developer certificate. Click **Done**.
3. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only do this once.

Requires macOS 13 or later on Apple silicon. Drift updates itself after that.

### Hotkeys

| Keys | Action |
|---|---|
| `⌥ Space` | Show or hide Drift |
| `⌥⌘ F` | Search music |
| `⌥⌘ P` | Play or pause (Drift or the app that's playing) |
| `⌥⌘ ← / →` | Previous / next |
| `⌥⌘ ↑ / ↓` | Volume |
| `⌥⌘ L` | Like the current song |

## Build from source

You need macOS 13+ and Xcode (or the Command Line Tools) with Swift 5.9 or later.

```sh
git clone https://github.com/faatehsultan/drift.git
cd drift
make run
```

`make run` builds `build/Drift.app` (including the bundled Sparkle and MediaRemote adapter frameworks) and launches it.

| Command | What it does |
|---|---|
| `make build` | Build `build/Drift.app` |
| `make run` | Build and launch |
| `make patch` / `minor` / `major` | Bump the version, commit and tag `vX.Y.Z` |
| `make setup-updates` | One-time: Sparkle tools and update-signing key |
| `make release` | Bump, build, publish a GitHub release and update the appcast |

## How it works

```
Sources/Drift
├── App/        App delegate, global hotkeys, Google sign-in window
├── Notch/      The panel over the notch, its shape, hover/peek logic, all UI state
├── Music/      YouTube Music's internal API client and JSON parsers
├── Playback/   Audio engine, player and queue, media from other apps
├── Features/   Calendar, tray and converter, tools, lyrics, Claude Code bridge
├── Settings/   Preferences and the settings window
└── UI/         Every screen (SwiftUI)
```

- **The notch** is a borderless panel above the menu bar, placed in its own window space so it doesn't blink during space swipes. Hover detection is a lightweight poll of the mouse position.
- **Music UI** is native SwiftUI. Search, browse and queue data come from YouTube Music's internal `youtubei` API, the same one the web app uses. Audio plays through a YouTube Music page that's never shown.
- **Other apps' media** is read through [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), which lets Apple's own `perl` read system Now Playing on macOS 15.4+.
- **Lyrics** come from [LRCLIB](https://lrclib.net).
- **Claude Code approvals** use a `PermissionRequest` hook that posts to a small server listening on `127.0.0.1:47823` only.
- **Updates** use [Sparkle](https://sparkle-project.org) with EdDSA-signed releases. The feed is `docs/appcast.xml`, served by GitHub Pages.

## Privacy

- No accounts, no analytics, no tracking.
- Notes, to-dos, the tray and clipboard history stay on your Mac. Copies from password managers are never recorded.
- Calendar and camera stay off until you allow them.
- Network calls go only to YouTube Music, LRCLIB (song name and artist, for lyrics) and the update feed.

## Roadmap

- [ ] Spotify as a full source (search, queue, library)
- [ ] Universal build for Intel Macs
- [ ] Notarized builds
- [ ] Hotkey remapping
- [ ] Weather and more Home widgets

Ideas welcome: [open an issue](https://github.com/faatehsultan/drift/issues/new/choose).

## Contributing

Bug reports, ideas and pull requests are very welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), and please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Acknowledgements

- [Sparkle](https://github.com/sparkle-project/Sparkle) for updates
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg for system Now Playing
- [LRCLIB](https://lrclib.net) for lyrics
- [ytmusicapi](https://github.com/sigma67/ytmusicapi), whose work documenting YouTube Music's API made this possible
- Inspired by the Dynamic Island and by notch apps like NotchNook and boring.notch

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for licenses.

## Disclaimer

Drift is an independent project. It isn't affiliated with or endorsed by Apple, Google/YouTube or Anthropic. It uses YouTube Music's unofficial API, which can change at any time.

## License

[GPL-3.0](LICENSE). You're free to use, study, change and share Drift. If you distribute a modified version, it must stay open source under the same license.
