import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/sources/online_link.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/download/download_sheet.dart';
import 'package:owntune/download/online_image.dart';
import 'package:owntune/download/search_online_screen.dart';
import 'package:owntune/settings/settings.dart';

import '../support/fakes.dart';

void main() {
  late FakeOnlineSource music;
  late FakeOnlineSource video;
  late FakeOnlineSource cloud;
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
    cloud = FakeOnlineSource(
      OnlineSourceId.soundcloud,
      results: [
        onlineResult(
          '111',
          source: OnlineSourceId.soundcloud,
          title: 'Smoke Signals',
          artist: 'SRY4U',
          album: null,
          subtitle: 'SRY4U · 442 plays',
        ),
        onlineResult(
          '555',
          source: OnlineSourceId.soundcloud,
          title: 'Second Track',
          artist: 'SRY4U',
          album: null,
          subtitle: 'SRY4U · 12 plays',
        ),
        onlineResult(
          '222',
          source: OnlineSourceId.soundcloud,
          title: 'Locked Track',
          artist: 'Someone',
          album: null,
          subtitle: 'Someone · 9 plays',
          availability: OnlineAvailability.protected,
        ),
        onlineResult(
          '333',
          source: OnlineSourceId.soundcloud,
          title: 'Snippet Track',
          artist: 'Someone',
          album: null,
          subtitle: 'Someone · 3 plays',
          availability: OnlineAvailability.previewOnly,
        ),
        onlineResult(
          '444',
          source: OnlineSourceId.soundcloud,
          title: 'Gone Track',
          artist: 'Someone',
          album: null,
          subtitle: 'Someone · 1 plays',
          availability: OnlineAvailability.unavailable,
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
        OnlineSourceId.soundcloud: cloud,
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

  testWidgets('the SoundCloud tab shows "Search SoundCloud" and searches the '
      'soundcloud source', (t) async {
    await open(t);
    expect(find.text('SoundCloud'), findsOneWidget);
    await t.tap(find.text('SoundCloud'));
    await t.pumpAndSettle();
    expect(find.text('Search SoundCloud'), findsOneWidget);
    await search(t, 'sry4u');
    expect(cloud.searches, ['sry4u']);
    expect(music.searches, isEmpty);
    expect(find.text('Smoke Signals'), findsOneWidget);
  });

  testWidgets('the tab choice is saved as soundcloud', (t) async {
    await open(t);
    await t.tap(find.text('SoundCloud'));
    await t.pumpAndSettle();
    expect(settings.saved.last.onlineSource, OnlineSourceId.soundcloud);
  });

  testWidgets('a SoundCloud row shows the square art with the duration on it '
      'and "SRY4U · 442 plays"', (t) async {
    await open(
      t,
      initial: AppSettings.defaults.copyWith(
        onlineSource: OnlineSourceId.soundcloud,
      ),
    );
    await search(t, 'sry4u');
    final row = find.byKey(const ValueKey('online-row-soundcloud:111'));
    expect(
      find.descendant(of: row, matching: find.text('SRY4U · 442 plays')),
      findsOneWidget,
    );
    // The duration sits on the art; the subtitle does not repeat it.
    expect(
      find.descendant(of: row, matching: find.text('3:08')),
      findsOneWidget,
    );
    final art = find.descendant(of: row, matching: find.byType(OnlineImage));
    expect(t.getSize(art), const Size(48, 48));
  });

  for (final (id, note) in [
    ('222', 'Protected'),
    ('333', 'Preview only'),
    ('444', 'Not available'),
  ]) {
    testWidgets('a $note row is dimmed, shows its note and opens no sheet '
        'on tap', (t) async {
      await open(
        t,
        initial: AppSettings.defaults.copyWith(
          onlineSource: OnlineSourceId.soundcloud,
        ),
      );
      await search(t, 'x');
      final row = find.byKey(ValueKey('online-row-soundcloud:$id'));
      expect(
        find.descendant(of: row, matching: find.text(note)),
        findsOneWidget,
      );
      final opacity = find.descendant(
        of: row,
        matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1),
      );
      expect(opacity, findsWidgets);
      expect(t.widget<InkWell>(row).onTap, isNull);
      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.byType(DownloadSheet), findsNothing);
    });
  }

  testWidgets('In Library and Downloading NN % show on SoundCloud rows', (
    t,
  ) async {
    await open(
      t,
      initial: AppSettings.defaults.copyWith(
        onlineSource: OnlineSourceId.soundcloud,
      ),
      inLibrary: ['soundcloud:111'],
      downloads: FakeDownloadController([
        downloadJob(
          1,
          '555',
          phase: DownloadPhase.downloading,
          received: 64,
          total: 100,
          source: OnlineSourceId.soundcloud,
        ),
      ]),
    );
    await search(t, 'x');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('online-row-soundcloud:111')),
        matching: find.text('In Library'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('online-row-soundcloud:555')),
        matching: find.text('Downloading 64 %'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping an available SoundCloud row opens the download sheet', (
    t,
  ) async {
    await open(
      t,
      initial: AppSettings.defaults.copyWith(
        onlineSource: OnlineSourceId.soundcloud,
      ),
    );
    await search(t, 'x');
    await t.tap(find.text('Smoke Signals'));
    await t.pumpAndSettle();
    expect(find.byType(DownloadSheet), findsOneWidget);
  });

  group('pasting a link', () {
    const ytLink = 'https://youtu.be/dQw4w9WgXcQ?si=abc&t=42';
    const scLink = 'https://soundcloud.com/sry4u/smoke-signals?si=x';

    Future<void> openOnSoundcloud(WidgetTester t) => open(
      t,
      initial: AppSettings.defaults.copyWith(
        onlineSource: OnlineSourceId.soundcloud,
      ),
    );

    testWidgets('submitting a YouTube link on the SoundCloud tab looks it up '
        'on the youtube source and opens the Download sheet', (t) async {
      video.linkResults['dQw4w9WgXcQ'] = onlineResult(
        'dQw4w9WgXcQ',
        source: OnlineSourceId.youtube,
        title: 'Rick Astley - Never Gonna Give You Up',
        artist: 'Rick Astley',
        album: null,
        channel: 'Rick Astley',
      );
      await openOnSoundcloud(t);
      await search(t, ytLink);
      expect(video.lookups, hasLength(1));
      expect((video.lookups.single as YoutubeLink).videoId, 'dQw4w9WgXcQ');
      expect(cloud.lookups, isEmpty);
      expect(music.searches, isEmpty);
      expect(cloud.searches, isEmpty);
      final sheet = find.byType(DownloadSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('Never Gonna Give You Up'),
        ),
        findsWidgets,
      );
      // The tab stays SoundCloud and the link is no recent search.
      expect(find.text('Search SoundCloud'), findsOneWidget);
      expect(settings.saved.where((s) => s.recentSearches.isNotEmpty), isEmpty);
    });

    testWidgets('pasting a SoundCloud link (text set at once) opens the sheet '
        'without submit', (t) async {
      await open(t);
      await t.enterText(find.byKey(const Key('online-search-field')), scLink);
      await t.pumpAndSettle();
      expect(cloud.lookups, hasLength(1));
      expect(
        (cloud.lookups.single as SoundcloudLink).url,
        Uri.parse('https://soundcloud.com/sry4u/smoke-signals'),
      );
      expect(find.byType(DownloadSheet), findsOneWidget);
      expect(music.searches, isEmpty);
    });

    testWidgets('typing a link one character at a time does not look it up '
        'before submit', (t) async {
      await open(t);
      for (var i = 1; i <= scLink.length; i++) {
        await t.enterText(
          find.byKey(const Key('online-search-field')),
          scLink.substring(0, i),
        );
      }
      await t.pumpAndSettle();
      expect(cloud.lookups, isEmpty);
      expect(find.byType(DownloadSheet), findsNothing);
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(cloud.lookups, hasLength(1));
      expect(find.byType(DownloadSheet), findsOneWidget);
    });

    testWidgets('a playlist link shows the playlist message, no Retry '
        'button, no lookup', (t) async {
      await open(t);
      await t.enterText(
        find.byKey(const Key('online-search-field')),
        'https://www.youtube.com/playlist?list=PLabcdefghij',
      );
      await t.pumpAndSettle();
      expect(find.text(playlistLinkMessage), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(video.lookups, isEmpty);
      expect(music.lookups, isEmpty);
      expect(find.byType(DownloadSheet), findsNothing);
    });

    testWidgets('a lookup error shows its message', (t) async {
      video.lookupError = const OnlineError('YouTube: Video unavailable');
      await open(t);
      await search(t, ytLink);
      expect(find.text('YouTube: Video unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(DownloadSheet), findsNothing);
      expect(find.byKey(const Key('online-loading')), findsNothing);
    });

    testWidgets('a late lookup does not open a sheet after the field '
        'changed', (t) async {
      video.lookupGate = Completer();
      await open(t);
      await t.enterText(find.byKey(const Key('online-search-field')), ytLink);
      await t.pump();
      expect(find.byKey(const Key('online-loading')), findsOneWidget);
      await t.enterText(find.byKey(const Key('online-search-field')), 'numb');
      await t.pump();
      video.lookupGate!.complete();
      await t.pumpAndSettle();
      expect(find.byType(DownloadSheet), findsNothing);
      expect(find.byKey(const Key('online-loading')), findsNothing);
    });

    testWidgets('a lookup shows a spinner and then restores the previous '
        'results', (t) async {
      await open(t);
      await search(t, 'numb');
      expect(find.text('In the End'), findsOneWidget);
      video.lookupGate = Completer();
      await t.enterText(find.byKey(const Key('online-search-field')), ytLink);
      await t.pump();
      expect(find.byKey(const Key('online-loading')), findsOneWidget);
      video.lookupGate!.complete();
      await t.pumpAndSettle();
      expect(find.byType(DownloadSheet), findsOneWidget);
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(find.byType(DownloadSheet), findsNothing);
      expect(find.text('In the End'), findsOneWidget);
    });

    final field = find.byKey(const Key('online-search-field'));
    const playlist = 'https://www.youtube.com/playlist?list=PLabcdefghij';

    testWidgets('clearing the field after a link error with no earlier '
        'search brings back the recent searches', (t) async {
      await open(
        t,
        initial: AppSettings.defaults.copyWith(recentSearches: ['numb']),
      );
      await t.enterText(field, playlist);
      await t.pumpAndSettle();
      expect(find.text(playlistLinkMessage), findsOneWidget);
      await t.enterText(field, '');
      await t.pumpAndSettle();
      expect(find.text(playlistLinkMessage), findsNothing);
      expect(find.text('Recent'), findsOneWidget);
    });

    testWidgets('editing the field after a link error shows the recent '
        'searches again', (t) async {
      await open(
        t,
        initial: AppSettings.defaults.copyWith(recentSearches: ['numb']),
      );
      await t.enterText(field, playlist);
      await t.pumpAndSettle();
      await t.enterText(field, '$playlist.');
      await t.pumpAndSettle();
      expect(find.text(playlistLinkMessage), findsNothing);
      expect(find.text('Recent'), findsOneWidget);
    });

    testWidgets('editing the field after a link error shows the previous '
        'results again', (t) async {
      await open(t);
      await search(t, 'numb');
      await t.enterText(field, playlist);
      await t.pumpAndSettle();
      expect(find.text(playlistLinkMessage), findsOneWidget);
      expect(find.text('In the End'), findsNothing);
      await t.enterText(field, 'numb2');
      await t.pumpAndSettle();
      expect(find.text(playlistLinkMessage), findsNothing);
      expect(find.text('In the End'), findsOneWidget);
    });

    testWidgets('pasting a link over a link of the same length opens the '
        'new one', (t) async {
      const other = 'https://youtu.be/aaaaaaaaaaa?si=abc&t=42';
      expect(other.length, ytLink.length);
      await open(t);
      await t.enterText(field, ytLink);
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(find.byType(DownloadSheet), findsNothing);
      await t.enterText(field, other);
      await t.pumpAndSettle();
      expect(video.lookups.map((l) => (l as YoutubeLink).videoId), [
        'dQw4w9WgXcQ',
        'aaaaaaaaaaa',
      ]);
      expect(find.byType(DownloadSheet), findsOneWidget);
    });

    testWidgets('pasting text around a link, which is no link as a whole, '
        'does not look it up', (t) async {
      await open(t);
      await t.enterText(field, 'a $ytLink b');
      await t.pumpAndSettle();
      expect(video.lookups, isEmpty);
    });

    testWidgets('a paste while a search is running cancels it and shows the '
        'recent searches afterwards', (t) async {
      music.searchGate = Completer();
      await open(
        t,
        initial: AppSettings.defaults.copyWith(recentSearches: ['older']),
      );
      await t.enterText(field, 'numb');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pump();
      expect(find.byKey(const Key('online-loading')), findsOneWidget);
      video.lookupGate = Completer();
      await t.enterText(field, ytLink);
      await t.pump();
      expect(video.lookups, hasLength(1));
      music.searchGate!.complete();
      video.lookupGate!.complete();
      await t.pumpAndSettle();
      expect(find.byType(DownloadSheet), findsOneWidget);
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(find.text('In the End'), findsNothing);
      expect(find.byKey(const Key('online-loading')), findsNothing);
      expect(find.text('Recent'), findsOneWidget);
    });

    testWidgets('switching the tab while the field holds a link does not '
        'search the earlier query again', (t) async {
      await open(t);
      await search(t, 'numb');
      expect(music.searches, ['numb']);
      await t.enterText(field, playlist);
      await t.pumpAndSettle();
      await t.tap(find.text('Videos'));
      await t.pumpAndSettle();
      expect(video.searches, isEmpty);
      expect(music.searches, ['numb']);
    });

    testWidgets('entering the same link again after editing during its '
        'lookup, then submitting, looks it up again', (t) async {
      video.lookupGate = Completer();
      await open(t);
      await t.enterText(field, ytLink);
      await t.pump();
      expect(video.lookups, hasLength(1));
      await t.enterText(field, 'numb');
      await t.pump();
      // Entered by typing (one character at a time), so no paste fires.
      for (var i = 1; i <= ytLink.length; i++) {
        await t.enterText(field, ytLink.substring(0, i));
      }
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pump();
      expect(video.lookups, hasLength(2));
      video.lookupGate!.complete();
      await t.pumpAndSettle();
      expect(find.byType(DownloadSheet), findsOneWidget);
    });

    testWidgets('a normal query still searches', (t) async {
      await open(t);
      await search(t, 'AC/DC');
      expect(music.searches, ['AC/DC']);
      expect(music.lookups, isEmpty);
      expect(video.lookups, isEmpty);
      expect(cloud.lookups, isEmpty);
      expect(settings.saved.last.recentSearches, ['AC/DC']);
    });
  });
}
