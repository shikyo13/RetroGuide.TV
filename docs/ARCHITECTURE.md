# Architecture

RetroGuide.TV has two parts:

- **`Packages/RetroGuideKit`**: a platform-independent Swift package with all of
  the logic that doesn't need UIKit. It builds and tests on macOS with
  `swift test`.
- **`App/`**: the tvOS app: SwiftUI views, the playback engines and app state.

## RetroGuideKit

| Area | What it does |
| --- | --- |
| `Models/` | `MediaItem`, `MediaVersion`, `MediaLibrary`, `ServerAccount`, playback settings and track selection. |
| `Library/` | `LibraryIndex` merges server snapshots (removing cross-server duplicates) and precomputes normalized attributes; `GenreTaxonomy` maps raw genres to `GenreCategory`. |
| `Channels/` | `ChannelRule` (declarative filters), the curated catalog (`Resources/curated-channels.json`), dynamic channels, and `LineupBuilder`, which resolves everything into a lineup. |
| `Scheduling/` | `ChannelTimeline` computes what's on at any time from a fixed epoch; `PlaylistArranger` implements the orderings. |
| `Search/` | `ProgramSearchIndex` finds titles and their next airing. |
| `MediaServers/` | The `MediaServerClient` protocol and the Plex implementation (linking, discovery, indexing, streams, track selection). |

### Scheduling

A channel's content is sorted into a stable order. Time since the epoch is
divided into cycles, each exactly as long as the channel's total runtime. Each
cycle is a permutation of the channel's items produced by a seeded generator
(seed = channel id + cycle number), so every cycle has the same length and
locating the program at any instant needs only a division and a binary search.
Nothing is stored, and every device shows the same schedule.

### Adding a media server backend

Implement `MediaServerClient` (libraries, items, streams, track selection,
artwork URLs, reachability), add a case to `ServerKind`, create the client in
`ServerRegistry`, and add a sign-in step to onboarding. Features only talk to
the protocol.

### Adding a built-in channel

Add an entry to `Resources/curated-channels.json` with a unique `id` and a
`number` below 90. Rules use canonical `categories`; see `GenreCategory`.

## App

| Area | What it does |
| --- | --- |
| `Composition/` | `AppModel` (phases, lineup, preferences, tuner), `ServerLibrary` (accounts, snapshots, parallel indexing, reachability), `ServerRegistry` (clients). |
| `Services/Playback/` | `Tuner` (channel logic, schedule boundaries, retries) and the `PlaybackEngine`s: `MPVPlaybackEngine` (libmpv) and `AVPlaybackEngine`. |
| `Features/Watch/` | The live picture, player chrome and the guide. The live picture is one full-screen surface that is scaled into the guide preview or picture-in-picture, so the video engine never resizes. |
| `DesignSystem/` | `DesignTokens`, `Typography`, `Theme`/`ThemeCatalog` and shared components. Views use these rather than literal values. |

### Conventions

- Swift 6 with strict concurrency.
- No magic numbers: constants live in named namespaces next to the code that
  uses them.
- Views are small and composed; styling comes from the design system.
- Memory: artwork is downsampled and cached with bounded caches, and the player
  uses bounded network buffers.
