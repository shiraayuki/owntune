import 'package:drift/drift.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/update/app_version.dart';

/// What the update check knows between app starts.
class UpdateRecord {
  const UpdateRecord({this.lastCheck, this.latest, this.dismissed});

  /// When the last successful check ran.
  final DateTime? lastCheck;

  /// The latest release that check found.
  final AppVersion? latest;

  /// The version whose banner the user closed.
  final AppVersion? dismissed;

  UpdateRecord copyWith({
    DateTime? lastCheck,
    AppVersion? latest,
    AppVersion? dismissed,
  }) => UpdateRecord(
    lastCheck: lastCheck ?? this.lastCheck,
    latest: latest ?? this.latest,
    dismissed: dismissed ?? this.dismissed,
  );
}

/// Keeps the [UpdateRecord]; tests use an in-memory one.
abstract interface class UpdateStore {
  Future<UpdateRecord> read();

  Future<void> write(UpdateRecord record);
}

/// [UpdateStore] as three rows in the `settings_entries` table. Malformed
/// values read as null.
class DbUpdateStore implements UpdateStore {
  DbUpdateStore(this._db);

  final AppDatabase _db;

  static const _lastCheckKey = 'update_last_check';
  static const _latestKey = 'update_latest';
  static const _dismissedKey = 'update_dismissed';
  static const _keys = [_lastCheckKey, _latestKey, _dismissedKey];

  @override
  Future<UpdateRecord> read() async {
    final rows = await (_db.select(
      _db.settingsEntries,
    )..where((e) => e.key.isIn(_keys))).get();
    final values = {for (final r in rows) r.key: r.value};
    final millis = int.tryParse(values[_lastCheckKey] ?? '');
    AppVersion? version(String key) {
      final v = values[key];
      return v == null ? null : AppVersion.parse(v);
    }

    return UpdateRecord(
      lastCheck: millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      latest: version(_latestKey),
      dismissed: version(_dismissedKey),
    );
  }

  @override
  Future<void> write(UpdateRecord record) async {
    final values = {
      _lastCheckKey: record.lastCheck?.millisecondsSinceEpoch.toString(),
      _latestKey: record.latest?.toString(),
      _dismissedKey: record.dismissed?.toString(),
    };
    await _db.batch((b) {
      for (final MapEntry(:key, :value) in values.entries) {
        if (value == null) {
          b.deleteWhere(_db.settingsEntries, (e) => e.key.equals(key));
        } else {
          b.insert(
            _db.settingsEntries,
            SettingsEntriesCompanion.insert(key: key, value: value),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
    });
  }
}
