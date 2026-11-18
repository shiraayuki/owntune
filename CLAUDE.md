# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projekt

owntune ist ein mobiler Musikplayer für **lokale Dateien** (iOS & Android): importieren, abspielen, Metadaten/Cover/Alben/Playlists verwalten. Kein Streaming, kein Account, komplett offline.

**Stand:** M0 (Grundgerüst) ist abgeschlossen und auf dem iPhone abgenommen. Die App ist ein einziger Bildschirm, der den Status des Rust-Kerns zeigt. Nächster Meilenstein: M1 (Import & Bibliothek). Designs und Pläne liegen unter `docs/superpowers/`.

## Rahmenbedingungen, die jede Entscheidung prägen

- Entwicklung auf **Linux, ohne Mac**. Täglicher Loop: Flutter als **Linux-Desktop-App** (`flutter run -d linux`) oder im **Android-Emulator**, mit Hot Reload.
- **iOS wird nie lokal gebaut.** Die `.ipa` entsteht nur in GitHub Actions (`.github/workflows/ios.yml`) und wird per SideStore auf das iPhone geladen (kostenlose Apple-ID, App läuft nach 7 Tagen ab).
- Der iOS-Workflow läuft **nur bei Versions-Tags `v*` oder manuell** (`gh workflow run iOS`), nicht bei jedem Push – macOS-Runner haben oft lange Wartezeiten. Standard ist der Intel-Runner `macos-15-intel`, weil arm64-Runner (`macos-latest`) zeitweise gar nicht zugeteilt wurden; per Dispatch-Input umschaltbar.
- iOS-spezifisches Verhalten (Hintergrundwiedergabe, Sperrbildschirm, Dateien-App) ist **nur auf dem echten iPhone** testbar. Plattformcode klein halten und hinter Schnittstellen kapseln; Logik muss unter Linux testbar bleiben. Bei iOS-sensibler Arbeit zwischendurch manuell einen iOS-Build anstoßen.
- Ohne Mac gibt es auf dem iPhone keine Logs. Fehler beim Start müssen deshalb **in der UI sichtbar** sein statt die App abstürzen zu lassen (Muster: `loadCoreStatus` → `CoreFailed` mit kopierbarem Text).
- Linux-Ziel ist nur Entwicklungshilfe, kein Produkt.

## Tech-Stack und gepinnte Versionen

Flutter **3.50.0** (gepinnt in beiden Workflows über `FLUTTER_VERSION`) · Dart 3.14 · Rust stable · flutter_rust_bridge **2.13.0** · lofty **0.25.5**.

- flutter_rust_bridge muss an **drei Stellen exakt gleich** sein: `pubspec.yaml`, `rust/Cargo.toml` (`=2.13.0`) und das installierte `flutter_rust_bridge_codegen` (in `ci.yml` als `FRB_VERSION`). Sonst schlägt `RustLib.init()` zur Laufzeit fehl.
- Seit Flutter 3.47 ist `package:flutter/material.dart` veraltet → **`package:material_ui/material_ui.dart`** importieren (sonst meldet `flutter analyze` Infos und die CI schlägt fehl).
- Geplant für spätere Meilensteine (noch nicht eingebunden): Riverpod, just_audio + audio_service (Linux: `just_audio_media_kit`), drift, file_picker. Pakete erst mit dem Meilenstein hinzufügen, der sie braucht.

## Befehle

Lokale Werkzeuge: Flutter in `~/.local/share/flutter`, Cargo-Binaries in `~/.cargo/bin` (beide im `PATH` über `~/.bashrc`).

```bash
flutter pub get
flutter run -d linux                                # Haupt-Entwicklungsziel
flutter analyze                                     # muss "No issues found!" melden
flutter test                                        # Unit- und Widget-Tests (ohne Rust)
flutter test test/app/core_status_test.dart         # einzelne Testdatei
flutter test --plain-name "zeigt App-Namen"         # einzelner Test
flutter test integration_test -d linux              # Integrationstests mit echtem Rust-Kern
(cd rust && cargo test && cargo clippy -- -D warnings && cargo fmt --check)
flutter_rust_bridge_codegen generate                # nach JEDER Änderung an rust/src/api/
```

iOS-Release: `git tag vX.Y.Z && git push --tags` (oder `gh workflow run iOS`), danach `.ipa` aus dem Artifact `owntune-ipa` laden.

## Architektur

```
lib/
  main.dart            # lädt den Rust-Kern (loadCoreStatus) und startet OwntuneApp
  app/                 # App-Start, Startbildschirm, CoreStatus
  src/rust/            # GENERIERT von flutter_rust_bridge – nicht von Hand ändern
rust/                  # Rust-Crate rust_lib_owntune
  src/api/             # alles hier wird nach Dart exportiert (init.rs, metadata.rs)
  src/frb_generated.rs # GENERIERT
rust_builder/          # cargokit-Glue: baut Rust bei jedem `flutter build` für die Zielplattform mit
integration_test/      # Tests gegen die echte native Bibliothek
```

Geplante Ordner für spätere Meilensteine: `lib/features/` (library, player, editor, playlists, import), `lib/data/` (db, repositories, `sources/` als Abstraktion „Quelle“ für ein späteres Download-Feature), `lib/services/` (audio, metadata).

**Rust-Brücke:** Funktionen in `rust/src/api/*.rs` werden per `flutter_rust_bridge_codegen generate` nach `lib/src/rust/api/*.dart` übersetzt (z. B. `supported_formats()` → `supportedFormats()`; `#[frb(sync)]` = synchroner Aufruf). Generierter Code ist eingecheckt; die CI generiert neu und schlägt fehl, wenn sich dabei etwas ändert. Der Codegen löscht keine veralteten Dateien – nach dem Entfernen eines Rust-Moduls die zugehörige `.dart`-Datei von Hand löschen.

**Testbarkeit:** Code, der Rust aufruft, bekommt die Rust-Funktionen als optionale Parameter (siehe `loadCoreStatus({init, formats})`), damit Unit-/Widget-Tests ohne native Bibliothek laufen. Echte Rust-Aufrufe werden in `integration_test/` geprüft.

## Grundsätze für kommende Meilensteine

- **Dateiablage:** Importierte Dateien werden in einen app-eigenen Bibliotheksordner kopiert (z. B. `Documents/Library/`), weil iOS keinen dauerhaften Zugriff auf fremde Ordner erlaubt. Duplikaterkennung per Hash. Auf iOS soll der Ordner in der Dateien-App sichtbar sein (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`).
- **Metadaten:** Die Datenbank ist die Quelle der Wahrheit für die Anzeige; Änderungen werden zusätzlich über `lofty` in die Datei-Tags zurückgeschrieben (ID3, Vorbis, MP4). Cover als Thumbnails im Cache.
- **Download-Feature ist nicht im Umfang** – nur die Abstraktion in `data/sources/` vorbereiten.

**Datenmodell (Entwurf):** Track (id, filePath, fileHash, title, artist, albumId, trackNumber, discNumber, duration, year, genre, coverPath, addedAt, playCount, lastPlayedAt) · Album (id, title, albumArtist, year, coverPath, isUserCreated) · Playlist (id, name, coverPath, createdAt) · PlaylistEntry (playlistId, trackId, position).

## Meilensteine

- **M0 Grundgerüst** – ✅ erledigt.
- **M1 Import & Bibliothek** – MP3, M4A/AAC, FLAC, OGG, WAV; Mehrfachimport, Kopieren, Hash-Duplikate, Tags+Cover auslesen; Ansichten Songs/Alben/Interpreten mit Suche und Sortierung. *Fertig:* 50 Dateien importiert und korrekt gruppiert.
- **M2 Player** – Steuerung, Warteschlange, Shuffle/Repeat, Mini-/Vollbild-Player, Hintergrund + Sperrbildschirm (`UIBackgroundModes: audio`), Zustand nach Neustart. *Fertig:* läuft auf dem iPhone bei gesperrtem Bildschirm und lässt sich steuern.
- **M3 Metadaten-Editor** – Felder bearbeiten, Cover wählen/zuschneiden/entfernen, Mehrfachbearbeitung, Rückschreiben in Tags.
- **M4 Alben & Playlists** – eigene Alben, Playlists mit Drag & Drop und eigenem Cover.
- **M5 Feinschliff** – Teilen-Menü/„Öffnen mit …“, dynamische Farben aus dem Cover, Dark Mode, Statistiken.

Nicht im Umfang: Download/Suche externer Quellen, Cloud-Sync, Accounts, Streaming, Store-Veröffentlichung.

## Entscheidungen und offene Fragen

Entschieden: Rust/`lofty` von Anfang an (M0) · Repo öffentlich · iOS-Builds nur für Releases. Aktuell genutzt: Sideloading per SideStore (TestFlight bleibt als Option offen).

Offen (nicht eigenmächtig festlegen): Dateien kopieren oder (unter Android) verlinken? · Welche Formate sind Pflicht? · Design-Richtung? · Linux später als echte Desktop-Version?
