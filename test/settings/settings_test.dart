import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/settings/settings.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });
  tearDown(() => db.close());

  AccentPreset preset(String name) =>
      kAccentPresets.firstWhere((p) => p.name == name);

  test('presets are the seven accents in order', () {
    expect(kAccentPresets.map((p) => p.name), [
      'Coral',
      'Amber',
      'Lime',
      'Teal',
      'Sky',
      'Violet',
      'Pink',
    ]);
    expect(kAccentPresets.first.color, const Color(0xffff7a59));
  });

  test('load on an empty database returns the defaults', () async {
    final s = await repo.load();
    expect(s.mode, AppearanceMode.system);
    expect(s.accent, preset('Coral').color);
    expect(s.accent, AppSettings.defaults.accent);
  });

  test('save then load round-trips', () async {
    final saved = AppSettings(
      mode: AppearanceMode.dark,
      accent: preset('Sky').color,
    );
    await repo.save(saved);
    final loaded = await repo.load();
    expect(loaded.mode, AppearanceMode.dark);
    expect(loaded.accent, preset('Sky').color);

    await repo.save(
      AppSettings(mode: AppearanceMode.light, accent: preset('Pink').color),
    );
    final again = await repo.load();
    expect(again.mode, AppearanceMode.light);
    expect(again.accent, preset('Pink').color);
  });

  test('stores accent as lowercase hex without #', () async {
    await repo.save(
      AppSettings(mode: AppearanceMode.system, accent: preset('Lime').color),
    );
    final row = await (db.select(
      db.settingsEntries,
    )..where((t) => t.key.equals('accent'))).getSingle();
    expect(row.value, 'c6f432');
    final mode = await (db.select(
      db.settingsEntries,
    )..where((t) => t.key.equals('appearance'))).getSingle();
    expect(mode.value, 'system');
  });

  test('an invalid stored accent falls back to Coral', () async {
    for (final bad in ['nothex', '#ff7a59', 'ff7a5', 'ff7a5900', '']) {
      await db
          .into(db.settingsEntries)
          .insertOnConflictUpdate(
            SettingsEntriesCompanion(
              key: const Value('accent'),
              value: Value(bad),
            ),
          );
      expect((await repo.load()).accent, preset('Coral').color, reason: bad);
    }
  });

  test('an unknown stored appearance falls back to system', () async {
    await db
        .into(db.settingsEntries)
        .insertOnConflictUpdate(
          SettingsEntriesCompanion(
            key: const Value('appearance'),
            value: const Value('sepia'),
          ),
        );
    expect((await repo.load()).mode, AppearanceMode.system);
  });
}
