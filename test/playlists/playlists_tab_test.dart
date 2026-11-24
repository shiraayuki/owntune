import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/playlist_repository.dart';
import 'package:owntune/playlists/playlist_artwork.dart';

import '../support/fakes.dart';

final _songs = [
  track(1, title: 'Amber Lights', album: 'A', artist: 'x', durationMs: 240000),
  track(2, title: 'Backroads', album: 'B', artist: 'x', durationMs: 240000),
];

/// A repository on an in-memory database, for tests that seed playlists.
PlaylistRepository _repo() {
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  addTearDown(db.close);
  return PlaylistRepository(
    db,
    LibraryStorage(Directory('/nonexistent/owntune')),
    hash: (_) => 'h',
  );
}

/// Database calls run in real time, outside the test's fake clock.
Future<T> _real<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

Future<void> _openTab(WidgetTester t) async {
  await t.tap(find.text('Playlists').last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('shows playlists with name and meta', (t) async {
    final repo = _repo();
    await _real(t, () async {
      final id = await repo.create('Rainy Days');
      await repo.addTracks(id, [1, 2]);
      await repo.create('Focus');
    });
    await pumpApp(t, songs: _songs, playlists: repo);
    await _openTab(t);

    expect(find.text('New Playlist'), findsOneWidget);
    expect(find.text('Rainy Days'), findsOneWidget);
    expect(find.text('2 songs · 8 min'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('0 songs · 0 min'), findsOneWidget);
    // Newest first.
    expect(
      t.getTopLeft(find.text('Focus')).dy,
      lessThan(t.getTopLeft(find.text('Rainy Days')).dy),
    );
  });

  testWidgets('without playlists the New Playlist row and a hint show', (
    t,
  ) async {
    await pumpApp(t, songs: _songs);
    await _openTab(t);
    expect(find.text('New Playlist'), findsOneWidget);
    expect(
      find.text('Create a playlist, or add songs with Add to Playlist.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Search Playlists'), findsOneWidget);
  });

  testWidgets('search filters by name, ignoring case', (t) async {
    final repo = _repo();
    await _real(t, () async {
      await repo.create('Rainy Days');
      await repo.create('Focus');
    });
    await pumpApp(t, songs: _songs, playlists: repo);
    await _openTab(t);

    await t.enterText(
      find.widgetWithText(TextField, 'Search Playlists'),
      'RAIN',
    );
    await t.pumpAndSettle();
    expect(find.text('Rainy Days'), findsOneWidget);
    expect(find.text('Focus'), findsNothing);

    await t.enterText(
      find.widgetWithText(TextField, 'Search Playlists'),
      'zzz',
    );
    await t.pumpAndSettle();
    expect(find.text('No results for "zzz"'), findsOneWidget);
  });

  testWidgets('a failing load shows the error', (t) async {
    await pumpApp(
      t,
      songs: _songs,
      overrides: [
        playlistsProvider.overrideWithValue(
          AsyncError(StateError('disk I/O error'), StackTrace.empty),
        ),
      ],
    );
    await _openTab(t);

    expect(find.text('Could not load your playlists'), findsOneWidget);
    expect(find.textContaining('disk I/O error'), findsOneWidget);
  });

  testWidgets('New Playlist row opens the sheet', (t) async {
    await pumpApp(t, songs: _songs);
    await _openTab(t);
    await t.tap(find.text('New Playlist'));
    await t.pumpAndSettle();
    expect(find.text('Add Cover'), findsOneWidget);
    expect(find.byKey(const Key('new-playlist-name')), findsOneWidget);
    expect(
      find.text('Without a cover, the playlist shows its first four albums.'),
      findsOneWidget,
    );
  });

  testWidgets('Create is disabled for a blank name', (t) async {
    await pumpApp(t, songs: _songs);
    await _openTab(t);
    await t.tap(find.text('New Playlist'));
    await t.pumpAndSettle();

    TextButton create() =>
        t.widget<TextButton>(find.byKey(const Key('new-playlist-create')));
    expect(create().onPressed, isNull);
    await t.enterText(find.byKey(const Key('new-playlist-name')), '   ');
    await t.pump();
    expect(create().onPressed, isNull);
    await t.enterText(find.byKey(const Key('new-playlist-name')), 'Mix');
    await t.pump();
    expect(create().onPressed, isNotNull);
  });

  testWidgets('Create stores the trimmed name and the playlist appears', (
    t,
  ) async {
    final repo = _repo();
    await pumpApp(t, songs: _songs, playlists: repo);
    await _openTab(t);
    await t.tap(find.text('New Playlist'));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const Key('new-playlist-name')),
      '  Sunday Morning ',
    );
    await t.pump();
    await t.tap(find.byKey(const Key('new-playlist-create')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('new-playlist-name')), findsNothing);
    expect(find.text('Sunday Morning'), findsOneWidget);
    expect(find.text('0 songs · 0 min'), findsOneWidget);
    final stored = await _real(t, () => repo.watchPlaylists().first);
    expect(stored.single.name, 'Sunday Morning');
  });

  testWidgets('Cancel closes the sheet without creating anything', (t) async {
    final repo = _repo();
    await pumpApp(t, songs: _songs, playlists: repo);
    await _openTab(t);
    await t.tap(find.text('New Playlist'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('new-playlist-name')), 'Mix');
    await t.tap(find.byKey(const Key('new-playlist-cancel')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('new-playlist-name')), findsNothing);
    expect(await _real(t, () => repo.watchPlaylists().first), isEmpty);
  });

  testWidgets('"+" menu: New Playlist opens the sheet', (t) async {
    await pumpApp(t, songs: _songs);
    await t.tap(find.byKey(const Key('import-button')));
    await t.pumpAndSettle();
    final item = t.widget<PopupMenuItem<Object>>(
      find.ancestor(
        of: find.text('New Playlist'),
        matching: find.byType(PopupMenuItem<Object>),
      ),
    );
    expect(item.enabled, isTrue);
    await t.tap(find.byKey(const Key('menu-new-playlist')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('new-playlist-name')), findsOneWidget);
  });

  group('PlaylistArtwork', () {
    final albums = [
      for (var i = 1; i <= 5; i++)
        track(i, album: 'Album $i', artist: 'x', cover: 'c$i.jpg'),
    ];

    Future<void> openWith(WidgetTester t, List<int> trackIds) async {
      final repo = _repo();
      await _real(t, () async {
        final id = await repo.create('Mix');
        await repo.addTracks(id, trackIds);
      });
      await pumpApp(t, songs: albums, playlists: repo);
      await _openTab(t);
    }

    Finder images() => find.descendant(
      of: find.byType(PlaylistArtwork),
      matching: find.byType(Image),
    );

    testWidgets('mosaic shows four covers when there is no custom cover', (
      t,
    ) async {
      await openWith(t, [1, 2, 3, 4, 5]);
      expect(images(), findsNWidgets(4));
    });

    testWidgets('fewer than four albums show the first cover alone', (t) async {
      await openWith(t, [3, 4]);
      expect(images(), findsOneWidget);
    });

    testWidgets('without covers the placeholder shows', (t) async {
      final repo = _repo();
      await _real(t, () async {
        final id = await repo.create('Mix');
        await repo.addTracks(id, [1]);
      });
      await pumpApp(t, songs: [track(1)], playlists: repo);
      await _openTab(t);
      expect(images(), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PlaylistArtwork),
          matching: find.byType(Icon),
        ),
        findsOneWidget,
      );
    });
  });
}
