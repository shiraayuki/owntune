import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/library/song_sort.dart';
import 'package:owntune/settings/settings.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('shows the Songs tab with the title row first', (t) async {
    await pumpApp(t);
    expect(find.text('Songs'), findsWidgets);
    expect(find.byIcon(CupertinoIcons.ellipsis), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.plus), findsWidgets);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
  });

  testWidgets('switches to the placeholder tabs', (t) async {
    await pumpApp(t);

    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    expect(find.text('Albums arrive in v0.3.'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.square_stack_fill), findsOneWidget);

    await t.tap(find.text('Artists'));
    await t.pumpAndSettle();
    expect(find.text('Artists arrive in v0.3.'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.person_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.square_stack), findsOneWidget);
  });

  testWidgets('Settings in the … menu calls the callback', (t) async {
    var opened = 0;
    await pumpApp(t, onOpenSettings: (_) => opened++);

    await t.tap(find.byIcon(CupertinoIcons.ellipsis));
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('+ and Import Music are disabled while an import runs', (
    t,
  ) async {
    final importer = FakeImporter();
    final picker = FakePicker(['/a/one.mp3']);
    await pumpApp(t, importer: importer, picker: picker);

    await t.tap(find.byKey(const Key('import-button')));
    await t.pumpAndSettle();
    expect(importer.calls, hasLength(1));

    // Hide the sheet so both buttons are reachable again.
    await t.tap(find.text('Hide – keep importing'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('import-button')));
    await t.tap(find.text('Import Music'));
    await t.pumpAndSettle();
    expect(picker.picks, 1);
    expect(importer.calls, hasLength(1));

    importer.finish(summary47);
    await t.pumpAndSettle();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('import-button')));
    await t.pumpAndSettle();
    expect(picker.picks, 2);
  });

  testWidgets('import flow: progress, hide, summary, done', (t) async {
    final importer = FakeImporter();
    final picker = FakePicker(List.generate(50, (i) => '/a/$i.mp3'));
    await pumpApp(t, importer: importer, picker: picker);

    await t.tap(find.byKey(const Key('import-button')));
    await t.pumpAndSettle();
    importer.progress(23, 50, 'Kettle & Pine – Dust & Gold.flac');
    await t.pumpAndSettle();

    expect(find.text('Importing music…'), findsOneWidget);
    expect(find.text('23 of 50 files'), findsOneWidget);
    expect(
      find.text('Reading tags: Kettle & Pine – Dust & Gold.flac'),
      findsOneWidget,
    );

    await t.tap(find.text('Hide – keep importing'));
    await t.pumpAndSettle();
    expect(find.text('Importing music…'), findsNothing);

    importer.finish(summary47);
    await t.pumpAndSettle();
    expect(find.text('Import complete'), findsOneWidget);
    expect(find.text('47 songs added'), findsOneWidget);

    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Import complete'), findsNothing);
    expect(picker.cleanups, 1);
  });

  testWidgets('follows the appearance setting', (t) async {
    await pumpApp(
      t,
      overrides: [
        initialSettingsProvider.overrideWithValue(
          const AppSettings(
            mode: AppearanceMode.dark,
            accent: Color(0xff5ab4ff),
          ),
        ),
      ],
    );
    final app = t.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    final context = t.element(find.text('Your library is empty'));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).colorScheme.primary, const Color(0xff5ab4ff));

    final container = ProviderScope.containerOf(context);
    expect(container.read(settingsProvider).mode, AppearanceMode.dark);
  });

  testWidgets('the … menu on Songs offers sorting with checkmarks', (t) async {
    await pumpApp(t, songs: [track(1, title: 'a')]);
    await t.tap(find.byIcon(CupertinoIcons.ellipsis));
    await t.pumpAndSettle();
    for (final label in [
      'Sort By',
      'Title',
      'Artist',
      'Album',
      'Recently Added',
      'Ascending',
      'Descending',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.byIcon(CupertinoIcons.checkmark), findsNWidgets(2));
  });

  testWidgets('choosing Artist re-sorts the songs and stores it', (t) async {
    final repo = FakeSettingsRepository();
    await pumpApp(
      t,
      songs: [
        track(1, title: 'Alpha', artist: 'Zed'),
        track(2, title: 'Beta', artist: 'Abe'),
      ],
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    expect(
      t.getTopLeft(find.text('Alpha')).dy,
      lessThan(t.getTopLeft(find.text('Beta')).dy),
    );

    await t.tap(find.byIcon(CupertinoIcons.ellipsis));
    await t.pumpAndSettle();
    await t.tap(find.text('Artist'));
    await t.pumpAndSettle();

    expect(repo.saved.last.songSort, SongSort.artist);
    expect(find.text('2 songs · sorted by artist'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('Beta')).dy,
      lessThan(t.getTopLeft(find.text('Alpha')).dy),
    );

    await t.tap(find.byIcon(CupertinoIcons.ellipsis));
    await t.pumpAndSettle();
    await t.tap(find.text('Descending'));
    await t.pumpAndSettle();
    expect(repo.saved.last.songSortDescending, isTrue);
    expect(repo.saved.last.songSort, SongSort.artist);
  });

  testWidgets('the … menu on Albums and Artists has only Settings', (t) async {
    await pumpApp(t);
    for (final tab in ['Albums', 'Artists']) {
      await t.tap(find.text(tab).last);
      await t.pumpAndSettle();
      await t.tap(find.byIcon(CupertinoIcons.ellipsis));
      await t.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget, reason: tab);
      expect(find.text('Sort By'), findsNothing, reason: tab);
      // Dismiss the menu.
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
    }
  });

  testWidgets('import summary shows over a pushed screen', (t) async {
    final importer = FakeImporter();
    await pumpApp(t, importer: importer, picker: FakePicker(['/a/one.mp3']));
    await t.tap(find.byKey(const Key('import-button')));
    await t.pumpAndSettle();
    await t.tap(find.text('Hide – keep importing'));
    await t.pumpAndSettle();

    Navigator.of(t.element(find.byType(AppShell))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('pushed'))),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('pushed'), findsOneWidget);

    importer.finish(summary47);
    await t.pumpAndSettle();
    expect(find.text('Import complete').hitTestable(), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Import complete'), findsNothing);
    expect(find.text('pushed'), findsOneWidget);
  });
}
