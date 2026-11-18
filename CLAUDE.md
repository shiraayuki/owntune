# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projekt

owntune ist ein mobiler Musikplayer für **lokale Dateien** (iOS & Android): importieren, abspielen, Metadaten/Cover/Alben/Playlists verwalten. Kein Streaming, kein Account, komplett offline.

**Stand:** Noch kein Code – das Repo steht vor Meilenstein M0. Abschnitte unten beschreiben die *geplante* Struktur; sobald Code existiert, hat der Code Vorrang und diese Datei sollte angepasst werden.

## Rahmenbedingungen, die jede Entscheidung prägen

- Entwicklung auf **Linux, ohne Mac**. Täglicher Loop: Flutter als **Linux-Desktop-App** oder im **Android-Emulator** mit Hot Reload.
- **iOS wird nie lokal gebaut.** iOS-Builds laufen in GitHub Actions auf einem macOS-Runner (`flutter build ios --no-codesign` → unsignierte `.ipa` als Artifact), Installation per Sideload (SideStore/iloader).
- iOS-spezifisches Verhalten (Hintergrundwiedergabe, Sperrbildschirm/Kontrollzentrum, Dateien-App) ist **nur auf dem echten iPhone** testbar. Plattformcode deshalb klein halten und hinter klaren Schnittstellen kapseln; Logik muss unter Linux testbar bleiben.
- Linux-Ziel ist (vorerst) nur Entwicklungshilfe, kein Produkt.

## Tech-Stack

Flutter (Dart) · Riverpod · just_audio + audio_service (unter Linux `just_audio_media_kit`) · drift (SQLite) · file_picker · Tag-Lesen/-Schreiben über Rust-Kern mit `lofty` via flutter_rust_bridge **oder** zunächst ein Dart-Paket (noch offen, s. u.).

## Befehle

```bash
flutter pub get
flutter run -d linux                     # Haupt-Entwicklungsziel
flutter run -d <android-emulator-id>     # flutter devices zeigt die IDs
flutter analyze
flutter test
flutter test test/pfad/zur_datei_test.dart          # einzelne Testdatei
flutter test --plain-name "Testname"                # einzelner Test
dart run build_runner build --delete-conflicting-outputs   # Codegen (drift, ggf. Riverpod)
```

Nach Änderungen an drift-Tabellen/DAOs (oder annotierten Riverpod-Providern) muss `build_runner` neu laufen.

## Geplante Architektur

```
lib/
  app/            # Routing, Theme, App-Start
  features/       # library, player, editor, playlists, import (UI + Feature-Logik)
  data/
    db/           # drift-Schema und DAOs
    repositories/
    sources/      # Abstraktion "Quelle" – jetzt nur lokal, später Download
  services/
    audio/        # audio_service-Handler
    metadata/     # Schnittstelle zum Tag-Backend (Rust oder Dart)
rust/             # optional: Rust-Kern (lofty, Scannen, Hashing)
```

Kernprinzipien, die über mehrere Teile hinweg gelten:

- **Dateiablage:** Importierte Dateien werden in einen app-eigenen Bibliotheksordner kopiert (z. B. `Documents/Library/`), weil iOS keinen dauerhaften Zugriff auf fremde Ordner erlaubt. Duplikaterkennung per Datei-Hash. Auf iOS soll der Ordner in der Dateien-App sichtbar sein (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`).
- **Metadaten:** Die Datenbank ist die Quelle der Wahrheit für die Anzeige; Änderungen werden **zusätzlich in die Datei-Tags zurückgeschrieben** (ID3, Vorbis, MP4). Cover liegen als Thumbnails im Cache.
- **Quellen-Abstraktion:** Ein Download-Feature kommt später und ist ausdrücklich nicht im Umfang. Nur die Abstraktion in `data/sources/` vorbereiten, keine Download-Logik bauen.
- `services/metadata/` ist eine Schnittstelle, damit das Tag-Backend (Dart ↔ Rust) austauschbar bleibt.

## Datenmodell (Entwurf)

- **Track:** id, filePath, fileHash, title, artist, albumId, trackNumber, discNumber, duration, year, genre, coverPath, addedAt, playCount, lastPlayedAt
- **Album:** id, title, albumArtist, year, coverPath, isUserCreated
- **Playlist:** id, name, coverPath, createdAt
- **PlaylistEntry:** playlistId, trackId, position

## Meilensteine

- **M0 Grundgerüst** – Flutter-Projekt (iOS/Android/Linux), CI (Lint+Test auf Linux, unsignierte `.ipa` auf macOS), optional flutter_rust_bridge. *Fertig:* leere App läuft unter Linux und per Sideload auf dem iPhone.
- **M1 Import & Bibliothek** – MP3, M4A/AAC, FLAC, OGG, WAV; Mehrfachimport, Kopieren, Hash-Duplikate, Tags+Cover auslesen; Ansichten Songs/Alben/Interpreten mit Suche und Sortierung.
- **M2 Player** – Steuerung, Warteschlange, Shuffle/Repeat, Mini-/Vollbild-Player, Hintergrund + Sperrbildschirm (`UIBackgroundModes: audio`), Zustand nach Neustart wiederherstellen.
- **M3 Metadaten-Editor** – Felder bearbeiten, Cover wählen/zuschneiden/entfernen, Mehrfachbearbeitung, Rückschreiben in Tags.
- **M4 Alben & Playlists** – eigene Alben, Playlists mit Drag & Drop und eigenem Cover.
- **M5 Feinschliff** – Teilen-Menü/„Öffnen mit …“, dynamische Farben aus dem Cover, Dark Mode, Statistiken.

Nicht im Umfang: Download/Suche externer Quellen, Cloud-Sync, Accounts, Streaming, Store-Veröffentlichung.

## Offene Entscheidungen (nicht eigenmächtig festlegen)

1. Rust/`lofty` von Anfang an oder zunächst Dart-Paket?
2. Sideloading oder TestFlight (99 $/Jahr)?
3. Dateien kopieren oder (unter Android) verlinken?
4. Welche Dateiformate sind wirklich Pflicht?
5. Design-Richtung?
6. Linux nur als Entwicklungshilfe oder später echte Desktop-Version?
