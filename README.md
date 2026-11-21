# Marquee

A minimal, Plex-style catalogue for a folder of movies and TV shows on macOS.
It reads your folder, identifies each title on TMDB (poster, backdrop, plot, year,
genres, rating, cast & crew, episode names and stills), opens files in IINA, tracks
what you've watched, and updates itself when new files land in the folder.

It never moves, renames or deletes your files.

## Build it (about 2 minutes)

You need macOS 14 or later and Apple's developer tools.

1. If you don't have them yet, open Terminal and run `xcode-select --install`.
2. In Terminal, go into this folder and run the build script:
   ```
   cd ~/Downloads/Marquee     # wherever you unzipped it
   ./build_app.sh
   ```
3. Open `build/Marquee.app`, or drag it into Applications.

Alternative: double-click `Package.swift` to open it in Xcode, then press ⌘R.

The first time, macOS asks whether Marquee may access your Documents folder. Say yes.
The app is signed only for your own Mac, so if Gatekeeper complains, right-click it and choose Open.

## First run

1. **TMDB key.** Make a free account at themoviedb.org, then go to Settings → API and copy
   either the *API Key* or the *API Read Access Token*. Paste it into Marquee.
2. **Folder.** Choose `Documents/BiglyBT Downloads` (or wherever your media is).

It then scans the folder and fetches metadata. The status in the top bar shows progress.

## How it reads your folder

It works on a flat downloads folder like yours as-is:

| On disk | Becomes |
|---|---|
| `Koyaanisqatsi (1982) [BluRay] [1080p] [YTS.AM]/` | Movie: *Koyaanisqatsi*, 1982 |
| `Perceval.1978.BDRip.x264-BiPOLAR[N1C]/` | Movie: *Perceval*, 1978 |
| `Broadchurch.S01.1080p.BluRay.x265-RARBG/` | Show: *Broadchurch*, season 1 |
| `Ugly Betty Season 3 Complete 720p…/` | Show: *Ugly Betty*, season 3 (merged with other seasons) |
| `Show.S02E05.mkv` loose in the folder | Show: episode 2×05 |

Rules:
- A folder is a **show** if its name has a season marker (`S01`, `Season 1`, `Saison 2`…)
  or it holds two or more `S01E02`-style files. Otherwise it's a **movie**, and the largest
  video inside is played.
- Season folders for the same show are merged into one show.
- `Sample` files and `Extras`, `Featurettes`, `Subs`… folders are ignored.

### If you want to organise (optional, but it removes all guessing)

```
BiglyBT Downloads/
├── Movies/
│   ├── Ran (1985)/…
│   └── La Jetee (1962).mkv
└── TV Shows/
    └── Broadchurch/
        ├── Season 1/Broadchurch.S01E01.mkv
        └── Season 2/…
```

Anything inside `Movies/` is treated as a movie and anything inside `TV Shows/` as a show.
Inside a show, episodes named `S01E01`, `1x01`, `Episode 1` or `01 - Title` all work.
You can mix both styles: organised subfolders and loose downloads side by side.

## Using it

- **Click a poster** for details. **Hover** and click ▶ to play straight away.
- For shows, **Play** starts the next unwatched episode ("Up Next"). If IINA's
  "auto-add files in the same folder" option is on, the following episodes queue up too.
- **Watch tracking:** by default, pressing Play marks a title or episode as watched.
  Turn that off in Settings if you'd rather tick things off by hand (✓ buttons, or right-click).
- **Wrong match?** Right-click → *Fix Match…* and pick the right title. Your choice is kept.
- **Search** (⌘F) looks at titles and at cast & crew. Clicking an actor or director finds
  everything else of theirs in your library.
- Shortcuts: ⌘1–4 switch tabs, ⌘R rescans, ⌘O changes folder, Esc goes back, Return plays.
- Settings → *Language* fetches plots and titles in French, Dutch, etc.
  (press *Re-download All Metadata* afterwards).

## Where things are stored

- Library, matches and watch history: `~/Library/Application Support/Marquee/library.json`
- Artwork cache: `~/Library/Caches/Marquee/Images`

Watch history is tied to the TMDB title, not the file path, so it survives renaming or
moving your files.

## Code map

```
Sources/Marquee/
  App/MarqueeApp.swift        app entry, menu commands, navigation state
  Core/FilenameParser.swift   "Ran (1985) [1080p]…" → title/year/season/episode
  Core/LibraryScanner.swift   folder → movies & shows
  Core/FolderWatcher.swift    FSEvents: rescans when the folder changes
  Core/TMDBClient.swift       search, details, credits, seasons
  Core/Library.swift          state, matching, watch tracking, persistence
  Core/ImageLoader.swift      artwork download + disk cache
  Core/Player.swift           opens files in IINA
  UI/…                        SwiftUI views
```

This product uses the TMDB API but is not endorsed or certified by TMDB.
