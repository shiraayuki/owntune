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
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/playlists/playlist_screen.dart';

import '../support/fakes.dart';

final _songs = [
  track(1, title: 'Amber Lights', album: 'A', artist: 'x', durationMs: 240000),
  track(2, title: 'Backroads', album: 'B', artist: 'x', durationMs: 240000),
  track(3, title: 'Coastline', album: 'C', artist: 'x', durationMs: 240000),
];

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

/// Pumps the app with one playlist "Rainy Days" holding [trackIds] and opens it.
Future<PlaylistRepository> _open(
  WidgetTester t,
  List<int> trackIds, {
  List<Track>? songs,
}) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repo = _repo();
  await _real(t, () async {
    final id = await repo.create('Rainy Days');
    await repo.addTracks(id, trackIds);
  });
  await pumpApp(
    t,
    songs: songs ?? _songs,
    playlists: repo,
    overrides: [
      trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
    ],
  );
  await t.tap(find.text('Playlists').last);
  await t.pumpAndSettle();
  await t.tap(find.text('Rainy Days'));
  await t.pumpAndSettle();
  return repo;
}

PlayerState _player(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(PlaylistScreen)))
        .read(playerProvider);

void main() {
  testWidgets('shows name, meta and songs in playlist order', (t) async {
    await _open(t, [3, 1, 2]);
    expect(find.byType(PlaylistScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavRow),
        matching: find.text('Playlists'),
      ),
      findsOneWidget,
    );
    expect(find.text('Rainy Days'), findsOneWidget);
    expect(find.text('3 songs · 12 min'), findsOneWidget);
    final ys = [
      for (final s in ['Coastline', 'Amber Lights', 'Backroads'])
        t.getTopLeft(find.text(s)).dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()));
  });

  testWidgets('an empty playlist shows a hint and disabled Play/Shuffle', (
    t,
  ) async {
    await _open(t, []);
    expect(
      find.text('This playlist is empty. Add songs with Add to Playlist.'),
      findsOneWidget,
    );
    final buttons = t.widget<PlayShuffleButtons>(
      find.byType(PlayShuffleButtons),
    );
    expect(buttons.onPlay, isNull);
    expect(buttons.onShuffle, isNull);
  });

  testWidgets('tapping the second copy of a duplicate plays from index 1', (
    t,
  ) async {
    await _open(t, [1, 2, 1]);
    await t.tap(find.text('Amber Lights').last);
    await t.pumpAndSettle();
    final queue = _player(t).queue;
    expect(queue.index, 2);
    expect([for (final e in queue.entries) e.trackId], [1, 2, 1]);
    expect(queue.source, 'Rainy Days');
  });

  testWidgets('Play starts at the first song with shuffle off', (t) async {
    await _open(t, [2, 1, 3]);
    await t.tap(find.text('Play'));
    await t.pumpAndSettle();
    final queue = _player(t).queue;
    expect(queue.shuffled, isFalse);
    expect(queue.index, 0);
    expect([for (final e in queue.entries) e.trackId], [2, 1, 3]);
  });

  testWidgets('Shuffle turns shuffle on', (t) async {
    await _open(t, [2, 1, 3]);
    await t.tap(find.text('Shuffle'));
    await t.pumpAndSettle();
    expect(_player(t).queue.shuffled, isTrue);
  });

  testWidgets('Remove from Playlist removes only that entry', (t) async {
    final repo = await _open(t, [1, 2, 1]);
    await t.longPress(find.text('Amber Lights').last);
    await t.pumpAndSettle();
    expect(find.text('Go to Album'), findsOneWidget);
    await t.tap(find.byKey(const Key('menu-remove-from-playlist')));
    await t.pumpAndSettle();

    expect(find.text('Amber Lights'), findsOneWidget);
    expect(find.text('Backroads'), findsOneWidget);
    expect(find.text('2 songs · 8 min'), findsOneWidget);
    final entries = await _real(t, () => repo.watchEntries().first);
    expect([for (final e in entries) e.trackId], unorderedEquals([1, 2]));
  });

  testWidgets('the song menu outside a playlist has no Remove entry', (
    t,
  ) async {
    await pumpApp(
      t,
      songs: _songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await t.longPress(find.text('Amber Lights'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu-remove-from-playlist')), findsNothing);
  });

  testWidgets('Delete Playlist asks and pops the page', (t) async {
    final repo = await _open(t, [1]);
    await t.tap(find.byKey(const Key('detail-more')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu-edit-playlist')), findsOneWidget);
    await t.tap(find.byKey(const Key('menu-delete-playlist')));
    await t.pumpAndSettle();
    expect(find.text('Delete "Rainy Days"?'), findsOneWidget);
    expect(find.text('The songs stay in your library.'), findsOneWidget);

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.byType(PlaylistScreen), findsOneWidget);

    await t.tap(find.byKey(const Key('detail-more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-delete-playlist')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(find.byType(PlaylistScreen), findsNothing);
    expect(await _real(t, () => repo.watchPlaylists().first), isEmpty);
    expect(find.text('Rainy Days'), findsNothing);
  });

  testWidgets('page pops when the playlist is deleted elsewhere', (t) async {
    final repo = await _open(t, [1]);
    final id = (await _real(t, () => repo.watchPlaylists().first)).single.id;
    await _real(t, () => repo.delete(id));
    await t.pumpAndSettle();
    expect(find.byType(PlaylistScreen), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping the "…" on a playlist row opens the song menu', (
    t,
  ) async {
    await _open(t, [2, 1]);
    await t.tap(find.byKey(const Key('song-more-1')));
    await t.pumpAndSettle();
    expect(find.text('Remove from Playlist'), findsOneWidget);
  });
}
