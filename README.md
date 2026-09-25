<p align="center">
  <img src="docs/images/banner.png" alt="RetroGuide.TV" width="720">
</p>

<p align="center">
  <strong>Your media library, on the air.</strong><br>
  A native Apple TV app that turns your Plex library into live TV channels with a classic program guide.
</p>

---

RetroGuide.TV builds dozens of always-on channels from the shows and movies you
already have: comedy, anime, sci-fi, 90s TV, 24/7 marathons of your favorite
series, and more. Turn it on and something is already playing. Flip channels with
the Siri Remote, drop into whatever's on mid-episode, and browse what's next in a
cable-style guide.

## Features

- **Automatic channels.** 50+ built-in genre, decade and format channels, plus
  channels for each library, TV network, large collection and long-running show.
  Channels with too little content are skipped, duplicates are removed, and the
  lineup scales to the size of your library.
- **Works with any library.** Genres are normalized across Plex agents and
  languages (for example "Sci-Fi & Fantasy", "Science Fiction" and "Komödie"), and
  anime is recognized even without an "Anime" genre tag.
- **Custom channels.** Combine genres, shows, networks, collections, decades,
  audiences and libraries, with a live preview of what the channel will air.
- **Real TV scheduling.** Every channel runs on a fixed clock, so with the same
  library and settings, the same program is on at the same time on every Apple TV. Choose Shuffle, Block
  Shuffle, Show Rotation or Marathon ordering per channel, and optionally align
  start times to the quarter or half hour.
- **Program guide.** A focus-driven grid with a live preview, "now" line,
  rating colors, show logos and artwork, and search with live results.
- **Channel surfing.** Swipe to change channels, with static between channels,
  a glowing channel number and an info banner, and Play/Pause for the last
  channel.
- **Direct play.** A bundled [libmpv](https://mpv.io) player plays MKV, HEVC,
  AV1, Dolby Vision, DTS, TrueHD and ASS subtitles directly, so your server
  doesn't have to transcode. Apple's player is available as a fallback.
- **Respects your Plex settings.** Audio and subtitle tracks follow your Plex
  account's language preferences and per-show choices.
- **Multiple servers.** Mix your own server with ones shared with you. The same
  title on several servers is kept once, offline servers drop out of the guide
  until they're back, and each server has its own quality and buffering
  settings for playback over the internet.
- **Themes.** Six themes (Classic Cable, Midnight, CRT Green, Amber Terminal,
  Synthwave, Mono) and optional CRT scanlines on menus.

## Requirements

- Apple TV running tvOS 17 or later (Apple TV 4K recommended)
- A Plex Media Server you own or that is shared with you. Servers outside your
  home must have Plex Remote Access enabled.

Jellyfin support is planned.

## Getting started

1. Open RetroGuide.TV and choose **Connect Plex**.
2. Go to [plex.tv/link](https://plex.tv/link) on your phone or computer (or scan
   the QR code) and enter the code shown on screen.
3. Pick a server and the libraries to include, then choose **Build My Channels**.

Live TV starts as soon as your first server is indexed. Add more servers later in
**Settings → Servers**.

### Remote controls

| Where | Button | Action |
| --- | --- | --- |
| Watching | Swipe up / down | Channel up / down |
| Watching | Swipe left / right | What's on now / next |
| Watching | Click | Open the guide |
| Watching | Play/Pause | Last channel |
| Guide | Click | Watch the highlighted channel |
| Guide | Play/Pause | Jump to Search and Settings |
| Anywhere | Menu | Back |

## How it works

- **Indexing.** RetroGuide.TV reads your library metadata from Plex once and
  caches it on the Apple TV, refreshing when it's more than six hours old. It
  never changes anything on your server and doesn't affect watch history.
- **Scheduling.** Each channel's schedule is computed from the channel's content
  and a fixed epoch rather than stored. Every schedule cycle plays each item on
  the channel once, in an order seeded by the channel and the cycle number.
  "What's on now" is simple arithmetic, so schedules never need rebuilding.
- **Playback.** Only one stream plays at a time. Channel changes wait a moment
  while you're flipping, and the previous stream is released before the next one
  starts. With the default player the server just sends the original file, like
  any direct play.

## Privacy

RetroGuide.TV has no accounts, analytics or ads, and collects no data. It talks
only to plex.tv (to link your account and find your servers) and to your media
servers. Access tokens are stored in the Apple TV keychain.

## Building from source

Requirements: macOS with Xcode 26 or later.

```bash
git clone <this repository>
cd RetroGuide
open RetroGuide.xcodeproj
```

Choose the **RetroGuide** scheme and an Apple TV simulator, then run. To run on a
device or archive, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`
and set your Apple Developer Team ID (that file is git-ignored).

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). After changing `project.yml`,
run `xcodegen generate` and commit the updated project.

Run the core library's tests with:

```bash
swift test --package-path Packages/RetroGuideKit
```

### Project layout

```
App/                      tvOS app (SwiftUI)
  Composition/            App state, servers, lineup building
  DesignSystem/           Tokens, themes and shared components
  Features/               Onboarding, Watch (player + guide), Search, Settings
  Services/               Playback engines, images, persistence
Packages/RetroGuideKit/   Platform-independent core: models, channel rules,
                          scheduling, search and the Plex client (unit tested)
Tools/BrandAssets/        Generates the app icon and Top Shelf images
Scripts/                  Build phase scripts
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a deeper tour.

## Contributing

Bug reports, ideas and pull requests are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

RetroGuide.TV is released under the [MIT License](LICENSE). It bundles
[MPVKit](https://github.com/mpvkit/MPVKit) (libmpv and FFmpeg) under the GNU LGPL
v3.0; see [NOTICE.md](NOTICE.md).

RetroGuide.TV is an independent project and is not affiliated with or endorsed
by Plex, Inc. Plex is a trademark of Plex, Inc.
