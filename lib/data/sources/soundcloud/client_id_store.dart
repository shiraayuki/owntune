import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_api.dart';

/// Keeps the scraped `client_id` between app starts.
abstract interface class SoundcloudClientIdStore {
  Future<String?> read();

  Future<void> write(String id);
}

/// [SoundcloudClientIdStore] as one row in the `settings_entries` table.
class DbSoundcloudClientIdStore implements SoundcloudClientIdStore {
  DbSoundcloudClientIdStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> read() async {
    final row = await (_db.select(
      _db.settingsEntries,
    )..where((e) => e.key.equals(clientIdSettingsKey))).getSingleOrNull();
    final value = row?.value;
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String id) => _db
      .into(_db.settingsEntries)
      .insertOnConflictUpdate(
        SettingsEntriesCompanion.insert(key: clientIdSettingsKey, value: id),
      );
}
