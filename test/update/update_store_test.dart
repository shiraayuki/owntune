import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/update/app_version.dart';
import 'package:owntune/update/update_store.dart';

void main() {
  late AppDatabase db;
  late DbUpdateStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DbUpdateStore(db);
  });
  tearDown(() => db.close());

  test('an empty database reads as nothing known', () async {
    final r = await store.read();
    expect(r.lastCheck, isNull);
    expect(r.latest, isNull);
    expect(r.dismissed, isNull);
  });

  test('write then read round-trips', () async {
    final at = DateTime.utc(2026, 11, 27, 9, 30, 12, 345);
    await store.write(
      UpdateRecord(
        lastCheck: at,
        latest: const AppVersion(0, 11, 0),
        dismissed: const AppVersion(0, 10, 1),
      ),
    );
    final r = await store.read();
    expect(r.lastCheck!.isAtSameMomentAs(at), isTrue);
    expect(r.latest, const AppVersion(0, 11, 0));
    expect(r.dismissed, const AppVersion(0, 10, 1));
  });

  test('writing null removes a value', () async {
    await store.write(
      const UpdateRecord(
        latest: AppVersion(0, 11, 0),
        dismissed: AppVersion(0, 11, 0),
      ),
    );
    await store.write(const UpdateRecord(latest: AppVersion(0, 12, 0)));
    final r = await store.read();
    expect(r.latest, const AppVersion(0, 12, 0));
    expect(r.dismissed, isNull);
  });

  test('malformed values read as null', () async {
    for (final (key, value) in [
      ('update_latest', 'x'),
      ('update_dismissed', 'v1'),
      ('update_last_check', 'yesterday'),
    ]) {
      await db
          .into(db.settingsEntries)
          .insertOnConflictUpdate(
            SettingsEntriesCompanion(key: Value(key), value: Value(value)),
          );
    }
    final r = await store.read();
    expect(r.latest, isNull);
    expect(r.dismissed, isNull);
    expect(r.lastCheck, isNull);
  });

  test('copyWith keeps what it is not given', () {
    const r = UpdateRecord(latest: AppVersion(0, 11, 0));
    final c = r.copyWith(dismissed: const AppVersion(0, 11, 0));
    expect(c.latest, const AppVersion(0, 11, 0));
    expect(c.dismissed, const AppVersion(0, 11, 0));
  });
}
