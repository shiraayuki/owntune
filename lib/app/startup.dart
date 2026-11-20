import 'dart:io';

import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/download/download_controller.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/player/audio_setup.dart' as audio;
import 'package:owntune/player/player_snapshot.dart';
import 'package:owntune/player/system_controls.dart';
import 'package:owntune/settings/settings.dart';
import 'package:owntune/src/rust/frb_generated.dart';

/// Result of [startUp].
sealed class StartupResult {
  const StartupResult();
}

final class StartupReady extends StartupResult {
  const StartupReady(
    this.db,
    this.storage,
    this.settings, {
    this.player,
    this.controls = const NoSystemControls(),
  });

  final AppDatabase db;
  final LibraryStorage storage;
  final AppSettings settings;

  /// The player as the last run left it; null if nothing (usable) was saved.
  final PlayerSnapshot? player;

  /// Lock screen / notification controls (none on Linux).
  final SystemControls controls;
}

final class StartupFailed extends StartupResult {
  const StartupFailed(this.message);

  final String message;
}

/// Loads the Rust core, sets up audio, opens the library storage and the database, removes
/// leftovers of interrupted imports and downloads and loads the settings.
///
/// Never throws: every error is returned as [StartupFailed] so the app can
/// show it. Without a Mac there is no other way to diagnose failures on the
/// iPhone. The parameters exist for tests; production passes none.
Future<StartupResult> startUp({
  Future<void> Function()? initRust,
  Future<void> Function()? initAudio,
  Future<SystemControls> Function()? initSystemControls,
  Future<LibraryStorage> Function()? openStorage,
  AppDatabase Function()? openDatabase,
  Future<Directory> Function()? downloadDir,
}) async {
  AppDatabase? db;
  try {
    await (initRust ?? RustLib.init)();
    await (initAudio ?? audio.initAudio)();
    final controls = await (initSystemControls ?? _defaultSystemControls)();
    final storage = await (openStorage ?? LibraryStorage.open)();
    await storage.ensure();
    db = (openDatabase ?? AppDatabase.open)();
    // drift opens the database lazily; this is its first query, so a broken
    // database file fails here and not later in the UI.
    await TrackRepository(db, storage).cleanupOrphans();
    try {
      await cleanupDownloads(await (downloadDir ?? defaultDownloadDir)());
    } on Object {
      // Leftover downloads are not worth a startup failure.
    }
    final settings = await SettingsRepository(db).load();
    PlayerSnapshot? player;
    try {
      player = await DbPlayerStateStore(db).load();
    } on Object {
      // A lost player state is not worth a startup failure.
    }
    return StartupReady(
      db,
      storage,
      settings,
      player: player,
      controls: controls,
    );
  } on Object catch (e) {
    try {
      await db?.close();
    } on Object {
      // The original error is the one worth showing.
    }
    return StartupFailed(e.toString());
  }
}

/// audio_service on phones; Linux (a development target) has none.
Future<SystemControls> _defaultSystemControls() async =>
    Platform.isIOS || Platform.isAndroid
    ? await AudioServiceControls.init()
    : const NoSystemControls();
