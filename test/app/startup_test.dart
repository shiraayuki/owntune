import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/startup.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/player/player_snapshot.dart';
import 'package:owntune/settings/settings.dart';

void main() {
  late Directory tmp;
  late LibraryStorage storage;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('owntune_startup_test');
    storage = LibraryStorage(Directory('${tmp.path}/library'));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<StartupResult> run({
    Future<void> Function()? initRust,
    Future<void> Function()? initAudio,
    Future<LibraryStorage> Function()? openStorage,
    AppDatabase Function()? openDatabase,
  }) => startUp(
    initRust: initRust ?? () async {},
    initAudio: initAudio ?? () async {},
    openStorage: openStorage ?? () async => storage,
    openDatabase: openDatabase ?? () => AppDatabase(NativeDatabase.memory()),
  );

  test('startUp returns StartupReady with the default settings', () async {
    final result = await run();
    expect(result, isA<StartupReady>());
    final ready = result as StartupReady;
    addTearDown(ready.db.close);
    expect(ready.storage, same(storage));
    expect(ready.settings, AppSettings.defaults);
    expect(storage.audioDir.existsSync(), isTrue);
    expect(storage.coversDir.existsSync(), isTrue);
  });

  test('startUp removes leftovers of interrupted imports', () async {
    await storage.ensure();
    final part = storage.audioFile('abc.part.mp3')..writeAsStringSync('x');
    final orphan = storage.coverFile('dead.png')..writeAsStringSync('x');

    final result = await run();
    addTearDown((result as StartupReady).db.close);

    expect(part.existsSync(), isFalse);
    expect(orphan.existsSync(), isFalse);
  });

  test('startUp is ready even if an orphan cannot be deleted', () async {
    await storage.ensure();
    final stuck = storage.audioFile('stuck.part.mp3')..writeAsStringSync('x');
    final orphan = storage.coverFile('dead.png')..writeAsStringSync('x');
    await Process.run('chmod', ['0555', storage.audioDir.path]);
    addTearDown(() => Process.run('chmod', ['0755', storage.audioDir.path]));

    final result = await run();

    expect(result, isA<StartupReady>(), reason: '$result');
    addTearDown((result as StartupReady).db.close);
    expect(stuck.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
  });

  test('startUp loads the stored settings', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await SettingsRepository(db).save(
      AppSettings(mode: AppearanceMode.dark, accent: kAccentPresets[4].color),
    );

    final result = await run(openDatabase: () => db);
    addTearDown(db.close);

    expect((result as StartupReady).settings.mode, AppearanceMode.dark);
    expect(result.settings.accent, kAccentPresets[4].color);
  });

  test(
    'startUp returns StartupFailed with the message when Rust init throws',
    () async {
      var dbOpened = false;
      final result = await run(
        initRust: () async => throw StateError('lib missing'),
        openDatabase: () {
          dbOpened = true;
          return AppDatabase(NativeDatabase.memory());
        },
      );
      expect(result, isA<StartupFailed>());
      expect((result as StartupFailed).message, contains('lib missing'));
      expect(dbOpened, isFalse);
    },
  );

  test(
    'startUp returns StartupFailed with the message when the DB open throws',
    () async {
      final result = await run(
        openDatabase: () => throw const FileSystemException('disk full'),
      );
      expect(result, isA<StartupFailed>());
      expect((result as StartupFailed).message, contains('disk full'));
    },
  );

  test(
    'startUp returns StartupFailed when the database fails on first use',
    () async {
      // drift opens lazily: a broken database file only fails on first query.
      final bad = File('${tmp.path}/broken.sqlite')
        ..writeAsStringSync('not a database ' * 100);
      final result = await run(
        openDatabase: () => AppDatabase(NativeDatabase(bad)),
      );
      expect(result, isA<StartupFailed>());
      expect((result as StartupFailed).message, isNotEmpty);
    },
  );

  test(
    'startUp returns StartupFailed when the storage cannot be opened',
    () async {
      final result = await run(
        openStorage: () async => throw StateError('no support dir'),
      );
      expect((result as StartupFailed).message, contains('no support dir'));
    },
  );

  test('startUp returns StartupFailed when audio setup fails', () async {
    final result = await run(
      initAudio: () async => throw StateError('no audio'),
    );
    expect(result, isA<StartupFailed>());
    expect((result as StartupFailed).message, contains('no audio'));
  });

  test('startUp returns the saved player state', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await DbPlayerStateStore(db).save(
      const PlayerSnapshot(trackIds: [4, 5], index: 1),
    );

    final result = await run(openDatabase: () => db);

    final player = (result as StartupReady).player!;
    expect(player.trackIds, [4, 5]);
    expect(player.index, 1);
  });

  test('a malformed saved player state is ignored', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.settingsEntries)
        .insert(
          SettingsEntriesCompanion.insert(
            key: DbPlayerStateStore.key,
            value: '{broken',
          ),
        );

    final result = await run(openDatabase: () => db);

    expect(result, isA<StartupReady>());
    expect((result as StartupReady).player, isNull);
  });
}
