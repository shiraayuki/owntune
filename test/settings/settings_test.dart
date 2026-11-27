import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/library/song_sort.dart';
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

  test('presets are the eight accents in order', () {
    expect(kAccentPresets.map((p) => p.name), [
      'Coral',
      'Amber',
      'Green',
      'Blue',
      'Violet',
      'Pink',
      'Grey',
      'White',
    ]);
    expect(kAccentPresets.first.color, const Color(0xffff6b4a));
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
      accent: preset('Blue').color,
    );
    await repo.save(saved);
    final loaded = await repo.load();
    expect(loaded.mode, AppearanceMode.dark);
    expect(loaded.accent, preset('Blue').color);

    await repo.save(
      AppSettings(mode: AppearanceMode.light, accent: preset('Pink').color),
    );
    final again = await repo.load();
    expect(again.mode, AppearanceMode.light);
    expect(again.accent, preset('Pink').color);
  });

  test('stores accent as lowercase hex without #', () async {
    await repo.save(
      AppSettings(mode: AppearanceMode.system, accent: preset('Green').color),
    );
    final row = await (db.select(
      db.settingsEntries,
    )..where((t) => t.key.equals('accent'))).getSingle();
    expect(row.value, '1ed760');
    final mode = await (db.select(
      db.settingsEntries,
    )..where((t) => t.key.equals('appearance'))).getSingle();
    expect(mode.value, 'system');
  });

  test('an invalid stored accent falls back to Coral', () async {
    for (final bad in [
      'nothex',
      '#ff6b4a',
      'ff6b4',
      'ff6b4a00',
      '',
      '123456',
    ]) {
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

  test('a stored pre-v0.9.1 accent maps to its successor', () async {
    const cases = {
      'ff7a59': 'Coral',
      'ffb340': 'Amber',
      'c6f432': 'Green',
      '3ee0c4': 'Green',
      '5ab4ff': 'Blue',
      'b38cff': 'Violet',
      'ff6fb5': 'Pink',
    };
    for (final MapEntry(key: old, value: name) in cases.entries) {
      await db
          .into(db.settingsEntries)
          .insertOnConflictUpdate(
            SettingsEntriesCompanion(
              key: const Value('accent'),
              value: Value(old),
            ),
          );
      expect((await repo.load()).accent, preset(name).color, reason: old);
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

  test('sort order round-trips', () async {
    await repo.save(
      AppSettings.defaults.copyWith(
        songSort: SongSort.added,
        songSortDescending: true,
      ),
    );
    final loaded = await repo.load();
    expect(loaded.songSort, SongSort.added);
    expect(loaded.songSortDescending, isTrue);
    final row = await (db.select(
      db.settingsEntries,
    )..where((t) => t.key.equals('songs_sort'))).getSingle();
    expect(row.value, 'added');
  });

  test('unknown stored sort falls back to title ascending', () async {
    for (final (key, value) in [
      ('songs_sort', 'genre'),
      ('songs_sort_desc', 'maybe'),
    ]) {
      await db
          .into(db.settingsEntries)
          .insertOnConflictUpdate(
            SettingsEntriesCompanion(key: Value(key), value: Value(value)),
          );
    }
    final loaded = await repo.load();
    expect(loaded.songSort, SongSort.title);
    expect(loaded.songSortDescending, isFalse);
    expect(AppSettings.defaults.songSort, SongSort.title);
  });

  test('online source and recent searches round-trip', () async {
    await repo.save(
      AppSettings.defaults.copyWith(
        onlineSource: OnlineSourceId.youtube,
        recentSearches: ['numb', 'get lucky'],
      ),
    );
    final loaded = await repo.load();
    expect(loaded.onlineSource, OnlineSourceId.youtube);
    expect(loaded.recentSearches, ['numb', 'get lucky']);
    expect(AppSettings.defaults.onlineSource, OnlineSourceId.ytmusic);
    expect(AppSettings.defaults.recentSearches, isEmpty);
  });

  test('online_source soundcloud round-trips', () async {
    await repo.save(
      AppSettings.defaults.copyWith(onlineSource: OnlineSourceId.soundcloud),
    );
    expect((await repo.load()).onlineSource, OnlineSourceId.soundcloud);
  });

  test('malformed online_recent and unknown online_source fall back', () async {
    for (final (key, value) in [
      ('online_recent', '{not json'),
      ('online_source', 'myspace'),
    ]) {
      await db
          .into(db.settingsEntries)
          .insertOnConflictUpdate(
            SettingsEntriesCompanion(key: Value(key), value: Value(value)),
          );
    }
    final loaded = await repo.load();
    expect(loaded.recentSearches, isEmpty);
    expect(loaded.onlineSource, OnlineSourceId.ytmusic);
  });

  group('SettingsNotifier recent searches', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
    });
    tearDown(() => container.dispose());

    List<String> recent() => container.read(settingsProvider).recentSearches;

    test('addRecentSearch trims, dedupes case-insensitively, newest first, '
        'keeps 10', () async {
      final n = container.read(settingsProvider.notifier);
      for (var i = 0; i < 11; i++) {
        await n.addRecentSearch('q$i');
      }
      expect(recent(), hasLength(10));
      expect(recent().first, 'q10');
      expect(recent(), isNot(contains('q0')));
      await n.addRecentSearch('  Q5 ');
      expect(recent().first, 'Q5');
      expect(recent().where((q) => q.toLowerCase() == 'q5'), hasLength(1));
      await n.addRecentSearch('   ');
      expect(recent().first, 'Q5');
      expect((await repo.load()).recentSearches, recent());
    });

    test('removeRecentSearch removes it', () async {
      final n = container.read(settingsProvider.notifier);
      await n.addRecentSearch('numb');
      await n.addRecentSearch('lucky');
      await n.removeRecentSearch('numb');
      expect(recent(), ['lucky']);
    });
  });

  test('normalizeVolume defaults to true when nothing is stored', () async {
    expect(AppSettings.defaults.normalizeVolume, isTrue);
    expect((await repo.load()).normalizeVolume, isTrue);
  });

  test('normalizeVolume false survives save and load', () async {
    await repo.save(AppSettings.defaults.copyWith(normalizeVolume: false));
    expect((await repo.load()).normalizeVolume, isFalse);
  });

  test('a malformed normalize_volume value loads as true', () async {
    await db
        .into(db.settingsEntries)
        .insertOnConflictUpdate(
          SettingsEntriesCompanion(
            key: const Value('normalize_volume'),
            value: const Value('nope'),
          ),
        );
    expect((await repo.load()).normalizeVolume, isTrue);
  });

  test('checkForUpdates round-trips and defaults to on', () async {
    expect(AppSettings.defaults.checkForUpdates, isTrue);
    expect((await repo.load()).checkForUpdates, isTrue);
    await repo.save(AppSettings.defaults.copyWith(checkForUpdates: false));
    expect((await repo.load()).checkForUpdates, isFalse);
    await db
        .into(db.settingsEntries)
        .insertOnConflictUpdate(
          const SettingsEntriesCompanion(
            key: Value('check_updates'),
            value: Value('garbage'),
          ),
        );
    expect((await repo.load()).checkForUpdates, isTrue);
  });
}
