# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

owntune is a mobile music player for **local files** (iOS & Android): import, play, and manage metadata/covers/albums/playlists. No streaming, no account, fully offline.

**Status:** M1 is split into two releases. **v0.2.0** contains: import (copy + hash duplicates + tags/cover via Rust), drift database, Songs tab, delete from library, and Settings (appearance + accent). **v0.3.0** completes M1: Albums, Artists, Playlists (empty placeholder until M4) and Search alongside Songs, with inline per-tab filtering, album/artist detail screens, Songs sort menu (stored in the settings) with A–Z index, a "+" menu (Import Music; New Playlist and Search Online disabled placeholders), and "Go to Album/Artist" in the song menu. **v0.3.1** regroups the tabs: four tabs (Home as a placeholder, Search, Library with Songs | Albums | Artists sub-tabs, each with its own search, and Playlists); the app opens on Library while Home is a placeholder. M1's "done when" still has to be checked on the iPhone. **v0.4.0** (first half of M2) plays music inside the app: tap a song and its list becomes the queue, mini player on every screen, full-screen Now Playing with scrubber and repeat (off/all/one), Up Next (reorder, remove, clear), Play Next/Later in the song menu, Play on album/artist pages, play counts. Shuffle controls are shown disabled. **v0.4.1** completes M2 apart from shuffle: playback continues in the background and with the screen locked, lock screen / Control Center / Android notification show the song with cover and offer play/pause/next/previous/scrubbing (audio_service), pauses by the system (calls, other apps) show in the player, and the player is restored paused at its position after a restart. M2's "done when" still has to be checked on the iPhone. Specs, plans and mockups live in `docs/superpowers/`, `docs/mockups/m1-v3/` (the M1 screens) and `docs/mockups/m2-v1/` (the four-tab layout and the M2 player).

**Language:** Everything in the repo — code, comments, tests, docs, commit messages, CI step names, UI strings — is in English. (Commits before 2026-11-18 are partly German; history is not rewritten.)

## Constraints that shape every decision

- Development happens on **Linux, without a Mac**. Daily loop: Flutter as a **Linux desktop app** (`flutter run -d linux`) or in the **Android emulator**, with hot reload.
- **iOS is never built locally.** The `.ipa` is produced only by GitHub Actions (`.github/workflows/ios.yml`) and sideloaded with SideStore (free Apple ID; the app expires after 7 days).
- The iOS workflow runs **only on version tags `v*` or manually** (`gh workflow run iOS`), not on every push — macOS runners often have long queues. Default runner is the Intel `macos-15-intel`, because arm64 runners (`macos-latest`) at times were not assigned at all; switchable via a dispatch input.
- iOS-specific behavior (background playback, lock screen, Files app) is **only testable on the real iPhone**. Keep platform code small and behind interfaces; logic must stay testable on Linux. For iOS-sensitive work, trigger an iOS build manually in between.
- Without a Mac there are no logs on the iPhone. Startup failures must therefore be **visible in the UI** instead of crashing the app (pattern: `startUp()` never throws and returns `StartupFailed`, which `StartupErrorApp` shows as selectable text inside a scroll view; later errors such as a failed import or delete are shown in sheets or dialogs; the import sheets sit above the navigator via `MaterialApp.builder`, so they also show over pushed screens).
- The Linux target is a development aid only, not a product.

## Tech stack and pinned versions

Flutter **3.50.0** (pinned in both workflows via `FLUTTER_VERSION`) · Dart 3.14 · Rust stable · flutter_rust_bridge **2.13.0** · lofty **0.25.5**.

- flutter_rust_bridge must be **exactly equal in three places**: `pubspec.yaml`, `rust/Cargo.toml` (`=2.13.0`), and the installed `flutter_rust_bridge_codegen` (`FRB_VERSION` in `ci.yml`). Otherwise `RustLib.init()` fails at runtime.
- Since Flutter 3.47, `package:flutter/material.dart` is deprecated → import **`package:material_ui/material_ui.dart`** (otherwise `flutter analyze` reports infos and CI fails).
- Since 3.50, `package:flutter/cupertino.dart` is deprecated too → import **`package:cupertino_ui/cupertino_ui.dart`** (icons: `CupertinoIcons`).
- In use since v0.2.0: flutter_riverpod 3 (no codegen), drift + drift_flutter (+ drift_dev/build_runner), file_picker, path_provider, package_info_plus; Rust side: blake3.
- In use since v0.4.0: just_audio (iOS/Android), just_audio_media_kit + media_kit_libs_linux (Linux, needs system libmpv; CI installs `libmpv-dev`), audio_session (iOS/Android: music category, so the silent switch does not mute).
- In use since v0.4.1: audio_service (iOS/Android; `MainActivity` extends `AudioServiceActivity`, the manifest declares its service and media button receiver, `Info.plist` has `UIBackgroundModes: audio`). Add packages only with the milestone that needs them.
- **Linux runner links `libgcc_s` first** (`linux/runner/CMakeLists.txt`): `libflutter_linux_gtk.so` exports its own `_Unwind_*`, and LuaJIT inside libmpv segfaulted when it unwound through them. Keep that line when regenerating the Linux runner.
- **media_kit reports an unreadable file only as an event with an error code** and never completes the load; `JustAudioEngine.load` therefore also ends on that event.

## Commands

Local tools (all installed without sudo, on `PATH` via `~/.bashrc`): Flutter in `~/.local/share/flutter`, cargo binaries in `~/.cargo/bin`, Android SDK in `~/Android/Sdk` (`ANDROID_HOME`; platform 36, NDK 28.2.13676358), JDK 17 in `~/.local/share/jdk-17` (`JAVA_HOME`, also set via `flutter config --jdk-dir`). Android emulator AVD: `owntune_pixel` (Pixel 6, API 36, x86_64, KVM).

```bash
flutter pub get
flutter run -d linux                                # main development target
flutter analyze                                     # must report "No issues found!"
flutter test                                        # unit and widget tests (no Rust)
flutter test test/library/sort_key_test.dart        # single test file
flutter test --plain-name "shows section headers A and B"   # single test
flutter test integration_test -d linux              # integration tests with the real Rust core
(cd rust && cargo test && cargo clippy -- -D warnings && cargo fmt --check)
flutter_rust_bridge_codegen generate                # after EVERY change in rust/src/api/
dart run build_runner build --delete-conflicting-outputs   # after changing the drift schema (lib/data/db/)
tool/make_fixtures.sh                               # regenerate test/fixtures/audio (needs ffmpeg)
dart run tool/embed_fixtures.dart                   # after changing fixtures: embed them for on-device integration tests

emulator -avd owntune_pixel &                       # start the Android emulator (boots in ~30 s)
flutter run -d emulator-5554                        # run on the emulator with hot reload
flutter test integration_test -d emulator-5554      # integration tests with real Rust on Android
```

**iOS release:** `git tag vX.Y.Z && git push --tags` → the iOS workflow builds the `.ipa` with that version (`--build-name`, build number = run number) and creates a GitHub release with `owntune.ipa` and `source.json`. SideStore source (add once in SideStore): `https://github.com/shiraayuki/owntune/releases/latest/download/source.json`; generated by `tool/sidestore_source.dart` (tests in `test/tool/`). `gh workflow run iOS` builds an artifact only, no release.

## Architecture

```
lib/
  main.dart            # startUp() → OwntuneApp with provider overrides, or StartupErrorApp
  app/                 # startup, app shell (title row, tabs, "…" menu), theme, Riverpod providers, buttons
  data/                # drift database (db/, *.g.dart GENERATED), LibraryStorage, TrackRepository
  home/                # Home tab (placeholder until its content is decided)
  import/              # Importer (copy, hash duplicates, rollback), ImportController, picker, import sheets
  library/             # Library.from (albums/artists derived from tracks), sorting, search, Library tab with sub-tabs, detail screens, navigation
  player/              # AudioEngine (just_audio) + audio setup, PlayQueue, PlayerController, mini player, Now Playing, Up Next
  settings/            # AppSettings + SettingsRepository, settings sheet
  src/rust/            # GENERATED by flutter_rust_bridge – do not edit by hand
rust/                  # Rust crate rust_lib_owntune
  src/api/             # everything here is exported to Dart (init.rs, library.rs, metadata.rs)
  src/frb_generated.rs # GENERATED
rust_builder/          # cargokit glue: builds Rust for the target platform on every `flutter build`
test/fixtures/audio/   # small audio fixtures (made by tool/make_fixtures.sh, see its README)
test/support/fakes.dart # shared fakes and pumpApp() for widget tests
integration_test/      # tests against the real native library and a real database
  support/             # fixturesDir(): host folder on desktop, embedded copy (fixture_data.dart, GENERATED) on phones
tool/                  # build/release scripts
```

Planned for later milestones: `lib/data/sources/` (a "source" abstraction for a later download feature).

**Player** (`lib/player/`): `PlayerController` (Riverpod notifier) owns a pure `PlayQueue` (entries with their own keys, current index, source label, repeat) and drives an `AudioEngine` that plays one file at a time; tests use `FakeAudioEngine` (`pumpApp` overrides `audioEngineProvider`). The controller stores track ids and follows `tracksProvider`, so deleted songs leave the queue. The system controls sit behind the `SystemControls` interface (`lib/player/system_controls.dart`): `AudioServiceControls` on phones, `NoSystemControls` on Linux and in tests; `systemControlsSyncProvider` publishes the current song to them and sends their commands (play, pause, next, previous, seek) to the controller. The controller saves a `PlayerSnapshot` (track ids, index, source, repeat, position) as JSON in `settings_entries` after queue changes, on pause and every five seconds of playback, and restores it paused, without songs deleted since. The mini player lives in each Scaffold's bottom bar (shell and detail screens), so menus dim it.

**Startup sequence** (`lib/app/startup.dart`): `RustLib.init()` → `initAudio()` (media_kit on Linux, audio session on phones) → system controls (`AudioService.init` on phones, none on Linux) → `LibraryStorage.open()` + `ensure()` (`<ApplicationSupport>/library/{audio,covers}`) → `AppDatabase.open()` (`<ApplicationSupport>/owntune.sqlite`) → `cleanupOrphans()` (best effort: leftover `.part` files and files without a row) → load settings → load the saved player state (a broken one is ignored). Any error → `StartupFailed`.

**Data rules:** The DB stores file names only (`<blake3>.<ext>`, covers `<blake3-of-image>.<ext>`), never absolute paths, because the iOS container path changes on app updates. Each file is copied to `audio/<random>.part.<ext>` (lofty picks the parser by extension), renamed to `<blake3>.<ext>`, and only then gets its row; covers are written via `covers/<random>.part`.

**Drift codegen:** `lib/data/db/database.g.dart` is committed; CI runs `build_runner` and fails if anything changes (same as for the FRB code).

**Rust bridge:** Functions in `rust/src/api/*.rs` are translated to `lib/src/rust/api/*.dart` by `flutter_rust_bridge_codegen generate` (e.g. `supported_formats()` → `supportedFormats()`; `#[frb(sync)]` = synchronous call). Generated code is committed; CI regenerates it and fails if anything changes. The codegen does not delete stale files — after removing a Rust module, delete the matching `.dart` file by hand.

**Testability:** Code that calls Rust takes the Rust functions as parameters (`startUp({initRust, openStorage, openDatabase})`, `Importer(read:, supportedExtensions:)`), and widgets get their dependencies via Riverpod providers that tests override (`pumpApp` in `test/support/fakes.dart`). So unit/widget tests run without the native library. Real Rust calls and the real database are tested in `integration_test/`.

## Principles for upcoming milestones

- **File storage:** Imported files are copied into the app-owned library folder `<ApplicationSupport>/library/`, because iOS does not allow persistent access to foreign folders. Duplicates are detected by BLAKE3 hash. In M1 the folder is deliberately **not** visible in the Files app: users could delete files behind the database's back. Revisit this together with "Open with …" in M5.
- **Metadata:** The database is the source of truth for display; changes are additionally written back into the file tags via `lofty` (ID3, Vorbis, MP4). Covers: v0.2.0 stores each distinct embedded image once under its hash and downscales in the UI (`cacheWidth`); real thumbnails may come later.
- **Download feature is out of scope** — only prepare the abstraction in `data/sources/`.

**Data model:** The `tracks` and `settings_entries` tables in `lib/data/db/database.dart` are the source of truth. Albums and artists are derived from track tags in Dart (`Library.from` in `lib/library/library.dart`, fed by `libraryProvider`); every view, the search and the song menu read that one snapshot. There is no album table yet. Draft for later milestones: Album (id, title, albumArtist, year, coverFile, isUserCreated) · Playlist (id, name, coverFile, createdAt) · PlaylistEntry (playlistId, trackId, position). These also store file names only, never paths.

## Milestones

- **M0 Skeleton** – ✅ done (release `v0.1.0`).
- **M1 Import & library** – MP3, M4A/AAC, FLAC, WAV (OGG later); multi-file import, copying, hash duplicates, read tags + cover; Songs/Albums/Artists views with search and sorting. *Done when:* 50 files imported and grouped correctly. Released in two parts: `v0.2.0` (import, database, Songs, delete, settings) and `v0.3.0` (Albums, Artists, details, search, sort); `v0.3.1` regroups them into four tabs with a Library tab.
- **M2 Player** – controls, queue, shuffle/repeat, mini and full-screen player, background + lock screen (`UIBackgroundModes: audio`), restore state after restart. *Done when:* plays on the iPhone with the screen locked and can be controlled. Released in two parts: `v0.4.0` (in-app playback, no shuffle) and `v0.4.1` (background, lock screen, restore).
- **M3 Metadata editor** – edit fields, pick/crop/remove covers, bulk editing, write back to tags.
- **M4 Albums & playlists** – custom albums, playlists with drag & drop and custom cover.
- **M5 Polish** – share sheet / "Open with …", dynamic colors from the cover, statistics (dark mode already ships in v0.2.0).

Out of scope: download/search of external sources, cloud sync, accounts, streaming, store publishing.

## Decisions and open questions

Decided: Rust/`lofty` from the start (M0) · public repo · iOS builds only for releases · UI in English · copy files on both platforms (no linking) · formats MP3, M4A/AAC, FLAC, WAV, with OGG later · design per mockup v3: light = Paper (monochrome), dark = Midnight with a selectable accent. Currently used: sideloading via SideStore (TestFlight remains an option).

Open (do not decide unilaterally): Linux later as a real desktop version?
