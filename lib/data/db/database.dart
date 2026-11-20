import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Imported audio files. Only file names are stored, never absolute paths,
/// because the iOS container path changes on app updates.
///
/// [sourceKey] is unique through an index, because SQLite cannot add a
/// UNIQUE column to an existing table; NULLs stay allowed.
@TableIndex(name: 'tracks_source_key', columns: {#sourceKey}, unique: true)
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fileName => text().unique()();
  TextColumn get originalName => text()();
  TextColumn get contentHash => text().unique()();
  TextColumn get title => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  TextColumn get albumArtist => text().nullable()();
  TextColumn get genre => text().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get durationMs => integer()();
  TextColumn get coverFile => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();

  /// Where a downloaded track came from, e.g. `youtube:<videoId>`; null for
  /// imported files.
  TextColumn get sourceKey => text().nullable()();
}

/// Key/value app settings.
class SettingsEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [Tracks, SettingsEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens `<Application Support>/owntune.sqlite`. drift_flutter defaults to
  /// the Documents directory, which is user-visible on desktop and meant for
  /// user documents on iOS; the database is app-internal state. It sits next
  /// to the `library/` folder, never inside it.
  static AppDatabase open() => AppDatabase(
    driftDatabase(
      name: 'owntune',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    ),
  );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(tracks, tracks.sourceKey);
        await m.createIndex(tracksSourceKey);
      }
    },
  );
}
