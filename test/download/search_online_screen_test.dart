import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/download/download_sheet.dart';
import 'package:owntune/download/search_online_screen.dart';
import 'package:owntune/settings/settings.dart';

import '../support/fakes.dart';

void main() {
  late FakeOnlineSource music;
  late FakeOnlineSource video;
  late FakeSettingsRepository settings;

  setUp(() {
    music = FakeOnlineSource(
      OnlineSourceId.ytmusic,
      results: [
        onlineResult('abc'),
        onlineResult('def', title: 'In the End', album: 'Hybrid Theory'),
      ],
    );
    video = FakeOnlineSource(
      OnlineSourceId.youtube,
      results: [
        onlineResult(
          'vid',
          source: OnlineSourceId.youtube,
          title: 'Linkin Park - Numb (Official Music Video)',
          artist: 'Linkin Park',
          album: null,
          channel: 'Linkin Park',
        ),
      ],
    );
    settings = FakeSettingsRepository();
  });

  Future<void> open(
    WidgetTester t, {
    AppSettings initial = AppSettings.defaults,
    FakeDownloadController? downloads,
    List<String> inLibrary = const [],
  }) async {
    await pumpApp(
      t,
      songs: [
        for (final (i, key) in inLibrary.indexed)
          track(100 + i, title: 'Lib $i', sourceKey: key),
      ],
      onlineSources: {
        OnlineSourceId.ytmusic: music,
        OnlineSourceId.youtube: video,
      },
      downloads: downloads,
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        initialSettingsProvider.overrideWithValue(initial),
      ],
    );
    await t.tap(find.byKey(const Key('import-button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-search-online')));
    await t.pumpAndSettle();
  }

  Future<void> search(WidgetTester t, String query) async {
    await t.enterText(find.byKey(const Key('online-search-field')), query);
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
  }

  testWidgets('Search Online opens from the + menu', (t) async {
    await open(t);
    expect(find.byType(SearchOnlineScreen), findsOneWidget);
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
  });

  testWidgets('submitting searches the remembered source and stores the '
      'query', (t) async {
    await open(t);
    await search(t, ' linkin park ');
    expect(music.searches, ['linkin park']);
    expect(video.searches, isEmpty);
    expect(find.text('Numb'), findsOneWidget);
    expect(find.text('In the End'), findsOneWidget);
    expect(settings.saved.last.recentSearches, ['linkin park']);
  });

  testWidgets('switching to Videos re-runs the query and is remembered', (
    t,
  ) async {
    await open(t);
    await search(t, 'numb');
    await t.tap(find.text('Videos'));
    await t.pumpAndSettle();
    expect(video.searches, ['numb']);
    expect(
      find.text('Linkin Park - Numb (Official Music Video)'),
      findsOneWidget,
    );
    expect(settings.saved.last.onlineSource, OnlineSourceId.youtube);
  });

  testWidgets('the remembered source is selected when it opens', (t) async {
    await open(
      t,
      initial: AppSettings.defaults.copyWith(
        onlineSource: OnlineSourceId.youtube,
      ),
    );
    await search(t, 'numb');
    expect(video.searches, ['numb']);
    expect(music.searches, isEmpty);
  });

  testWidgets('rows show In Library and Downloading 64 %', (t) async {
    await open(
      t,
      inLibrary: ['youtube:abc'],
      downloads: FakeDownloadController([
        downloadJob(
          1,
          'def',
          phase: DownloadPhase.downloading,
          received: 64,
          total: 100,
        ),
      ]),
    );
    await search(t, 'linkin park');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('online-row-youtube:abc')),
        matching: find.text('In Library'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('online-row-youtube:def')),
        matching: find.text('Downloading 64 %'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('result rows do not rebuild on progress of another job', (
    t,
  ) async {
    final downloads = FakeDownloadController([
      downloadJob(
        1,
        'def',
        phase: DownloadPhase.downloading,
        received: 1,
        total: 100,
      ),
    ]);
    await open(t, downloads: downloads);
    await search(t, 'linkin park');
    // A row that did not rebuild keeps the very same child widgets.
    Widget firstText(String key) => t.widget(
      find
          .descendant(
            of: find.byKey(ValueKey('online-row-youtube:$key')),
            matching: find.byType(Text),
          )
          .first,
    );
    final def = firstText('def');
    final abc = firstText('abc');
    downloads.jobs = [
      downloadJob(
        1,
        'def',
        phase: DownloadPhase.downloading,
        received: 50,
        total: 100,
      ),
    ];
    await t.pump();
    expect(identical(firstText('def'), def), isFalse);
    expect(identical(firstText('abc'), abc), isTrue);
  });

  testWidgets('a recent search runs again on tap and can be swiped away', (
    t,
  ) async {
    await open(
      t,
      initial: AppSettings.defaults.copyWith(recentSearches: ['numb', 'lucky']),
    );
    expect(find.text('Recent'), findsOneWidget);
    await t.tap(find.text('numb'));
    await t.pumpAndSettle();
    expect(music.searches, ['numb']);
    expect(find.text('Numb'), findsOneWidget);

    await t.tap(find.byKey(const Key('search-clear')));
    await t.pumpAndSettle();
    expect(find.text('Recent'), findsOneWidget);
    await t.drag(find.text('lucky'), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(find.text('lucky'), findsNothing);
    expect(settings.saved.last.recentSearches, ['numb']);
  });

  testWidgets('a failing search shows its message and Retry', (t) async {
    music.searchError = const OnlineError('No connection');
    await open(t);
    await search(t, 'numb');
    expect(find.text('No connection'), findsOneWidget);
    music.searchError = null;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(music.searches, ['numb', 'numb']);
    expect(find.text('Numb'), findsOneWidget);
  });

  testWidgets('a search shows a spinner, then the results', (t) async {
    music.searchGate = Completer();
    await open(t);
    await t.enterText(find.byKey(const Key('online-search-field')), 'numb');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pump();
    expect(find.byKey(const Key('online-loading')), findsOneWidget);
    music.searchGate!.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('online-loading')), findsNothing);
    expect(find.text('Numb'), findsOneWidget);
  });

  testWidgets('no results says so', (t) async {
    music.results = [];
    await open(t);
    await search(t, 'zzzz');
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('tapping a row opens the download sheet', (t) async {
    await open(t);
    await search(t, 'numb');
    await t.tap(find.text('Numb'));
    await t.pumpAndSettle();
    expect(find.byType(DownloadSheet), findsOneWidget);
  });
}
