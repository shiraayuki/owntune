import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/startup.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/import/audio_file_picker.dart';
import 'package:owntune/settings/settings.dart';
import 'package:owntune/src/rust/api/metadata.dart';

import 'support/fixtures.dart';

/// Returns fixed paths instead of opening the system picker.
class _FixturePicker implements AudioFilePicker {
  _FixturePicker(this.paths);

  final List<String> paths;

  @override
  Future<List<String>> pick() async => paths;

  @override
  Future<void> clearTemporaryFiles() async {}
}

Future<void> pumpUntil(WidgetTester t, Finder finder) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $finder');
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump();
  }
  await t.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late StartupResult result;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('owntune_app_it');
    // Real Rust init; only the locations are redirected to a temp folder.
    result = await startUp(
      openStorage: () async => LibraryStorage(Directory('${tmp.path}/library')),
      openDatabase: () =>
          AppDatabase(NativeDatabase(File('${tmp.path}/owntune.sqlite'))),
    );
  });

  tearDownAll(() async {
    if (result case StartupReady(:final db)) await db.close();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('startUp with the real Rust core returns StartupReady', (
    t,
  ) async {
    expect(result, isA<StartupReady>(), reason: '$result');
    final ready = result as StartupReady;
    expect(ready.settings, AppSettings.defaults);
    expect(ready.storage.audioDir.existsSync(), isTrue);
    expect(supportedFormats(), ['mp3', 'm4a', 'aac', 'flac', 'wav']);
  });

  testWidgets('imports the fixtures through the UI and lists them', (t) async {
    final ready = result as StartupReady;
    final fixtures = fixturesDir();
    final picked = [
      for (final name in [
        'tagged.mp3',
        'tagged.flac',
        'tagged.m4a',
        'demo_3.wav',
        'unicode.mp3',
        'evening-walk.ogg',
        'broken.mp3',
      ])
        '${fixtures.path}/$name',
    ];

    await t.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(ready.db),
          storageProvider.overrideWithValue(ready.storage),
          initialSettingsProvider.overrideWithValue(ready.settings),
          filePickerProvider.overrideWithValue(_FixturePicker(picked)),
        ],
        child: const OwntuneApp(),
      ),
    );
    await pumpUntil(t, find.text('Your library is empty'));

    // First import: 5 added, nothing duplicated, 2 not supported.
    await t.tap(find.text('Import Music'));
    await pumpUntil(t, find.text('Import complete'));
    expect(find.text('7 files checked'), findsOneWidget);
    expect(find.text('5 songs added'), findsOneWidget);
    expect(find.textContaining('duplicate'), findsNothing);
    expect(find.text('2 files not supported'), findsOneWidget);
    expect(find.textContaining('evening-walk.ogg, broken.mp3'), findsOneWidget);

    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Import complete'), findsNothing);

    await pumpUntil(t, find.text('After the Rain'));
    expect(find.text('demo_3'), findsOneWidget);
    expect(find.text('Unknown Artist'), findsOneWidget);
    expect(find.byKey(const ValueKey('section-D')), findsOneWidget);
    // Covers are shown for the tracks that have one.
    expect(find.byType(Image), findsWidgets);

    // Second import of the same files: all supported ones are duplicates.
    await tapImport(t);
    await pumpUntil(t, find.text('Import complete'));
    expect(find.text('0 songs added'), findsOneWidget);
    expect(find.text('5 duplicates skipped'), findsOneWidget);
    expect(find.text('2 files not supported'), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();

    // Dispose the providers (and their database streams) before teardown.
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('settings show real stats and persist the appearance', (t) async {
    final ready = result as StartupReady;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(ready.db),
          storageProvider.overrideWithValue(ready.storage),
          initialSettingsProvider.overrideWithValue(ready.settings),
        ],
        child: const OwntuneApp(),
      ),
    );
    await pumpUntil(t, find.text('After the Rain'));

    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    // The five songs imported by the previous test and the pubspec version.
    await pumpUntil(t, find.text('5'));
    await pumpUntil(t, find.textContaining(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(find.textContaining(RegExp(r'^\d+ MB$')), findsOneWidget);

    await t.tap(find.text('Dark'));
    await t.tap(find.bySemanticsLabel('Teal'));
    await t.pumpAndSettle();

    // A fresh load from the database is what the next start sees.
    final stored = await t.runAsync(() => SettingsRepository(ready.db).load());
    expect(
      stored,
      const AppSettings(mode: AppearanceMode.dark, accent: Color(0xff3ee0c4)),
    );

    await t.pumpWidget(const SizedBox());
  });
}

/// Opens the "+" menu and chooses Import Music.
Future<void> tapImport(WidgetTester t) async {
  await t.tap(find.byKey(const Key('import-button')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('menu-import')));
  await t.pumpAndSettle();
}
