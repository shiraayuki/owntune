# M1: Import & Library – Design

Date: 2026-11-18 · Overall plan: `CLAUDE.md` · UI reference: `docs/mockups/m1-v3/` (agreed)

## Intent

M1 turns the empty skeleton into a usable music library: get audio files from the phone into owntune, read their metadata and covers, and browse them as songs, albums and artists. Playback is M2; M1 must produce a library that M2 can play without changes to how files and metadata are stored.

The riskiest part is getting files from the iPhone into the app's own storage via the system picker and reading them with the Rust core on the device. That part ships first (release `v0.2.0`) so it is verified on the real iPhone before the remaining views are built.

## Goals

- **Import:** pick one or many files with the system document picker; copy each into the app-owned library folder; read tags, duration and embedded cover; detect duplicates by content hash; show progress and a summary (added / duplicates skipped / not supported).
- **Formats:** MP3, M4A/AAC, FLAC, WAV. Everything else (including OGG) is reported as "not supported" and not copied.
- **Missing tags:** title falls back to the file name without extension, artist to "Unknown Artist"; tracks without an album tag appear in Songs and Artists but not in Albums; placeholder artwork when there is no embedded cover.
- **Library views (per mockup v3):** Songs (section headers + A–Z index), Albums (2-column grid), Album detail (track list by disc/track number), Artists (list), Artist detail (albums row + songs), Search across songs/albums/artists, "…" menu with sort options and Settings.
- **Sorting:** Songs by title, artist, album, recently added; ascending/descending. Albums by album artist then title; artists by name. Sorting ignores case and a leading "The ".
- **Delete from library:** long-press context menu on a song → confirmation → removes the DB row, the copied file and the cached cover; albums/artists that become empty disappear.
- **Settings:** appearance System / Light (Paper) / Dark (Midnight); accent color for dark mode (7 presets: Coral `#ff7a59` default, Amber `#ffb340`, Lime `#c6f432`, Teal `#3ee0c4`, Sky `#5ab4ff`, Violet `#b38cff`, Pink `#ff6fb5`); storage used and song count; app version. Persisted across restarts.
- **Persistence:** everything survives an app restart.

**Done when:** 50 files of mixed formats are imported on the iPhone, duplicates and an unsupported file are reported correctly, songs/albums/artists are grouped and sorted correctly, a song can be deleted, and all of it is still there after restarting the app.

## Non-goals

- Playback, queue, mini player (M2). Play/Shuffle buttons are shown per mockup but disabled.
- Editing metadata or covers (M3); custom albums and playlists (M4).
- OGG/Opus support, folder linking on Android, "Open with…"/share-sheet import (M5).
- Showing the library folder in the iOS Files app (see Decisions).

## Anti-goals

- An import that blocks the UI or crashes on a malformed file. One bad file must never abort the rest of the batch.
- Two copies of the same file in the library.
- Library rows pointing at files that no longer exist after a failed or cancelled import.

## Constraints

- Everything from `CLAUDE.md`: no Mac, iOS only verifiable on the device via a release tag, errors must be visible in the UI.
- Repo language is English, including UI strings.
- Light mode is monochrome (Paper); the accent color only applies in dark mode.

## Approaches

**Where the per-file work happens** (my call, accepted with the M1 recommendations)
- **A – One Rust call per file:** `read_track(path)` returns tags, duration, content hash and the embedded cover bytes in one call; Dart copies files, writes the DB and drives the UI. Few bridge calls, heavy work off the UI thread, reuses `lofty` from M0. **Chosen.**
- B – Dart-only metadata (a Dart tag package + Dart hashing): no FFI in the import path, but a second tag library next to `lofty`, which M3 needs for writing anyway.
- C – Rust owns the database too: one language for all data, but the Flutter state layer would have to mirror Rust state; drift on the Dart side is the simpler fit.

**Copy vs. link** (decided by the user: copy) — copy into the app's library folder on both platforms; one code path, stable paths, write access for M3.

**Release split** (decided by the user)
- `v0.2.0`: import pipeline, database, Songs tab, context menu with delete, Settings (appearance + accent).
- `v0.3.0`: Albums, Artists, detail screens, search, sort menu.

## Decisions

By the user:
- Copy files; formats MP3, M4A/AAC, FLAC, WAV; OGG later.
- UI per mockup v3, incl. person icon for Artists, v1 typography and import screens, titles inline with the "…" and "+" buttons.
- Light (Paper) + dark (Midnight) modes; accent color selectable in dark mode.
- Delete from library is part of M1.
- Two releases (`v0.2.0`, `v0.3.0`).

My calls (please check):
- **Library folder is not visible in the Files app in M1.** Files live under the app's Application Support directory. Reason: if users can delete or rename files there, the database silently points at missing files; handling that properly belongs with "Open with…" in M5. This defers the `UIFileSharingEnabled` idea from the original plan.
- **Content hash:** BLAKE3 over the whole file (Rust `blake3` crate). Files that differ only in tags count as different files.
- **Copied file name:** `<hash>.<ext>` in the library folder, so names never collide and the hash doubles as the duplicate key.
- **Covers:** the embedded cover is written once per distinct image as `covers/<blake3-of-image>.jpg|png` and referenced by tracks and albums; lists downscale on the Flutter side (`cacheWidth`), no image processing in Rust.
- **Album identity:** (album artist, falling back to track artist) + album title, case-insensitive. The album cover is the cover of its first track that has one; album year = the most common year among its tracks.
- **Artists** are derived from the track artist field (no separate table); "feat." credits are not split in M1.
- **Settings defaults:** appearance "System", accent Coral.
- **Settings storage:** a key-value table in the same drift database (no extra package).
- **Interrupted imports:** each file is copied to a temporary name and renamed only after its DB row is written; leftovers without a row are deleted at startup. There is no "Stop" button (per mockup v3, only "Hide – keep importing").
- **State management:** Riverpod (as planned); drift streams feed providers so views update live while an import runs.

## Left to the implementer

- Exact drift schema beyond the data model in `CLAUDE.md` (indices, column types), as long as the album identity rule above holds and migrations start at schema version 1.
- How the import runs concurrently (sequential is acceptable if the UI stays responsive and progress updates per file).
- Picker package: `file_picker` (as planned) unless it cannot return file paths for multi-select on iOS/Android; any replacement must still use the system document picker.
- Test fixtures: small generated audio files per format, committed under `test/fixtures/` (with/without tags, with cover, non-ASCII tags, a duplicate, an `.ogg`).
- Section index (A–Z) behavior details: letters without songs may be dimmed or skipped.
