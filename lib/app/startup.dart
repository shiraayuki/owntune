import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/settings/settings.dart';
import 'package:owntune/src/rust/frb_generated.dart';

/// Result of [startUp].
sealed class StartupResult {
  const StartupResult();
}

final class StartupReady extends StartupResult {
  const StartupReady(this.db, this.storage, this.settings);

  final AppDatabase db;
  final LibraryStorage storage;
  final AppSettings settings;
}

final class StartupFailed extends StartupResult {
  const StartupFailed(this.message);

  final String message;
}

/// Loads the Rust core, opens the library storage and the database, removes
/// leftovers of interrupted imports and loads the settings.
///
/// Never throws: every error is returned as [StartupFailed] so the app can
/// show it. Without a Mac there is no other way to diagnose failures on the
/// iPhone. The parameters exist for tests; production passes none.
Future<StartupResult> startUp({
  Future<void> Function()? initRust,
  Future<LibraryStorage> Function()? openStorage,
  AppDatabase Function()? openDatabase,
}) async {
  AppDatabase? db;
  try {
    await (initRust ?? RustLib.init)();
    final storage = await (openStorage ?? LibraryStorage.open)();
    await storage.ensure();
    db = (openDatabase ?? AppDatabase.open)();
    // drift opens the database lazily; this is its first query, so a broken
    // database file fails here and not later in the UI.
    await TrackRepository(db, storage).cleanupOrphans();
    final settings = await SettingsRepository(db).load();
    return StartupReady(db, storage, settings);
  } on Object catch (e) {
    try {
      await db?.close();
    } on Object {
      // The original error is the one worth showing.
    }
    return StartupFailed(e.toString());
  }
}
