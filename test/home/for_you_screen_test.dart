import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/playlist_repository.dart';
import 'package:owntune/home/home_cards.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/queue_source.dart';

import '../support/fakes.dart';

final _noon = clockProvider.overrideWithValue(() => DateTime(2026, 11, 24, 12));

Future<void> _tall(WidgetTester t) async {
  t.view.physicalSize = const Size(2000, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(OwntuneApp)));

PlayerState _state(WidgetTester t) => _container(t).read(playerProvider);

PlayerController _player(WidgetTester t) =>
    _container(t).read(playerProvider.notifier);

List<int> _ids(WidgetTester t) => [
  for (final e in _state(t).queue.entries) e.trackId,
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

Track _song(
  int id,
  String title, {
  String? album,
  int playCount = 0,
  DateTime? likedAt,
}) => track(
  id,
  title: title,
  artist: 'Juno Vale',
  album: album,
  playCount: playCount,
  likedAt: likedAt,
);

Finder _navBack(String label) =>
    find.descendant(of: find.byType(NavRow), matching: find.text(label));

void main() {
  testWidgets('tiles open their pages with the back label Home', (t) async {
    await _tall(t);
    final songs = [
      _song(1, 'Amber Lights', album: 'Dusk'),
      _song(2, 'Backroads', likedAt: DateTime(2026, 11, 20)),
    ];
    final repo = _repo();
    final id = (await t.runAsync(() async {
      final id = await repo.create('Roadtrip');
      await repo.addTracks(id, [1, 2]);
      return id;
    }))!;
    final home = FakeHomeRepository()
      ..recent = [
        RecentSource(
          QueueSourceKind.album,
          '${albumKeyOf(songs[0])!.artist}\u0000dusk',
          DateTime(2026, 11, 24, 11),
        ),
        RecentSource(
          QueueSourceKind.playlist,
          '$id',
          DateTime(2026, 11, 24, 10),
        ),
        RecentSource(QueueSourceKind.liked, null, DateTime(2026, 11, 24, 9)),
      ];
    await pumpApp(
      t,
      songs: songs,
      playlists: repo,
      home: home,
      overrides: [_noon],
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('home-tile-0')));
    await t.pumpAndSettle();
    expect(find.text('Amber Lights'), findsOneWidget);
    expect(_navBack('Home'), findsOneWidget);
    await tapBack(t);

    await t.tap(find.byKey(const Key('home-tile-1')));
    await t.pumpAndSettle();
    expect(find.text('Roadtrip'), findsOneWidget);
    expect(_navBack('Home'), findsOneWidget);
    await tapBack(t);

    await t.tap(find.byKey(const Key('home-tile-2')));
    await t.pumpAndSettle();
    expect(find.text('Liked Songs'), findsWidgets);
    expect(_navBack('Home'), findsOneWidget);
  });

  testWidgets('an artist tile opens the artist page with the back label Home', (
    t,
  ) async {
    await _tall(t);
    final songs = [
      _song(1, 'Amber Lights', album: 'Dusk'),
      _song(2, 'Backroads', album: 'Dusk'),
    ];
    final artistKey = Library.from(songs).artists.single.key;
    final home = FakeHomeRepository()
      ..recent = [
        RecentSource(QueueSourceKind.artist, artistKey, DateTime(2026, 11, 24)),
      ];
    await pumpApp(t, songs: songs, home: home, overrides: [_noon]);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('home-tile-0')));
    await t.pumpAndSettle();

    expect(find.text('Juno Vale'), findsWidgets);
    expect(find.text('Amber Lights'), findsOneWidget);
    expect(_navBack('Home'), findsOneWidget);
  });

  testWidgets('a paused queue shows no continue card and no shuffle '
      'buttons', (t) async {
    // Both were removed in v0.9.2 (the mini player covers resuming).
    await _tall(t);
    final songs = [
      _song(1, 'Amber Lights', likedAt: DateTime(2026, 11, 20)),
      _song(2, 'Backroads'),
    ];
    await pumpApp(t, songs: songs, overrides: [_noon]);
    await t.pumpAndSettle();
    await _player(t)
        .playList(songs, start: 1, source: QueueSource.playlist(3, 'Roadtrip'));
    await _player(t).togglePlay();
    await t.pumpAndSettle();
    expect(find.text('Continue listening'), findsNothing);
    expect(find.text('Shuffle All'), findsNothing);
    expect(find.text('Shuffle Liked'), findsNothing);
  });

  group('song cards', () {
    final songs = [for (var i = 1; i <= 5; i++) _song(i, 'Song $i')];
    FakeHomeRepository home() =>
        FakeHomeRepository()
          ..top = [for (var i = 1; i <= 5; i++) TrackPlayCount(i, 10 - i)];

    testWidgets('plays the row with an other source', (t) async {
      await _tall(t);
      final engine = FakeAudioEngine();
      await pumpApp(
        t,
        songs: songs,
        home: home(),
        engine: engine,
        overrides: [_noon],
      );
      await t.pumpAndSettle();
      final row = find.byKey(const Key('home-row-on-repeat'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('8 plays')),
        findsOneWidget,
      );
      await t.tap(find.descendant(of: row, matching: find.text('Song 2')));
      await t.pumpAndSettle();
      expect(engine.loaded, ['hash2.mp3']);
      expect(_ids(t), [1, 2, 3, 4, 5]);
      expect(_state(t).queue.index, 1);
      expect(
        _state(t).queue.source,
        const QueueSource(QueueSourceKind.other, 'On Repeat'),
      );
    });

    testWidgets('long-press opens the song menu', (t) async {
      await _tall(t);
      await pumpApp(
        t,
        songs: songs,
        home: home(),
        overrides: [
          _noon,
          trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        ],
      );
      await t.pumpAndSettle();
      final row = find.byKey(const Key('home-row-on-repeat'));
      await t.longPress(
        find.descendant(of: row, matching: find.text('Song 3')),
      );
      await t.pumpAndSettle();
      expect(find.text('Play Next'), findsOneWidget);
      expect(find.text('Play Later'), findsOneWidget);
    });
  });

  group('sections', () {
    testWidgets('empty sections are hidden', (t) async {
      await _tall(t);
      // No plays: On Repeat and Rediscover are empty, Never Played is not.
      await pumpApp(t, songs: [_song(1, 'Amber Lights')], overrides: [_noon]);
      await t.pumpAndSettle();
      expect(find.text('On Repeat'), findsNothing);
      expect(find.byKey(const Key('home-header-on-repeat')), findsNothing);
      expect(find.text('Rediscover'), findsNothing);
      expect(find.text('Recently Added'), findsNothing);
      expect(find.byKey(const Key('home-header-never-played')), findsOneWidget);
      expect(find.text('Never Played'), findsOneWidget);
    });

    testWidgets('Recently Added shows albums and opens the album', (t) async {
      await _tall(t);
      await pumpApp(
        t,
        songs: [_song(1, 'Amber Lights', album: 'Dusk')],
        overrides: [_noon],
      );
      await t.pumpAndSettle();
      final row = find.byKey(const Key('home-row-recently-added'));
      expect(
        find.byKey(const Key('home-header-recently-added')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Juno Vale')),
        findsOneWidget,
      );
      await t.tap(find.descendant(of: row, matching: find.text('Dusk')));
      await t.pumpAndSettle();
      expect(_navBack('Home'), findsOneWidget);
      expect(find.text('Amber Lights'), findsOneWidget);
    });

    testWidgets('rows show at most 10 cards', (t) async {
      await _tall(t);
      final songs = [for (var i = 1; i <= 12; i++) _song(i, 'Song $i')];
      await pumpApp(t, songs: songs, overrides: [_noon]);
      await t.pumpAndSettle();
      expect(find.byType(HomeSongCard), findsNWidgets(10));
    });
  });
}
