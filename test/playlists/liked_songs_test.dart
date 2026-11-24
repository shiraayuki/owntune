import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/queue_source.dart';
import 'package:owntune/playlists/liked_songs.dart';

import '../support/fakes.dart';

Track _song(int id, String title, {DateTime? likedAt}) => track(
  id,
  title: title,
  album: 'A',
  artist: 'x',
  durationMs: 240000,
  likedAt: likedAt,
);

final _songs = [
  _song(1, 'Amber Lights', likedAt: DateTime(2026, 11, 20)),
  _song(2, 'Backroads'),
  _song(3, 'Coastline', likedAt: DateTime(2026, 11, 22)),
  _song(4, 'Daybreak', likedAt: DateTime(2026, 11, 21)),
];

Future<void> _open(
  WidgetTester t,
  List<Track> songs, {
  Stream<List<Track>>? songsStream,
  FakeAudioEngine? engine,
}) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await pumpApp(
    t,
    songs: songs,
    songsStream: songsStream,
    engine: engine,
    overrides: [
      trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
    ],
  );
  await t.tap(find.text('Playlists').last);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('playlists-liked')));
  await t.pumpAndSettle();
}

PlayerState _player(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(LikedSongsScreen)))
        .read(playerProvider);

void main() {
  testWidgets('page lists liked songs newest first', (t) async {
    await _open(t, _songs);
    expect(find.byType(LikedSongsScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavRow),
        matching: find.text('Playlists'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(LikedSongsScreen),
        matching: find.text('Liked Songs'),
      ),
      findsOneWidget,
    );
    expect(find.text('3 songs · 12 min'), findsOneWidget);
    expect(find.text('Backroads'), findsNothing);
    final ys = [
      for (final s in ['Coastline', 'Daybreak', 'Amber Lights'])
        t.getTopLeft(find.text(s)).dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()));
  });

  testWidgets('a tie in likedAt puts the higher id first', (t) async {
    final same = DateTime(2026, 11, 20);
    await _open(t, [
      _song(1, 'Amber Lights', likedAt: same),
      _song(2, 'Backroads', likedAt: same),
    ]);
    expect(
      t.getTopLeft(find.text('Backroads')).dy,
      lessThan(t.getTopLeft(find.text('Amber Lights')).dy),
    );
  });

  testWidgets('tapping a song plays the list from it with source liked', (
    t,
  ) async {
    final engine = FakeAudioEngine();
    await _open(t, _songs, engine: engine);
    await t.tap(find.text('Daybreak'));
    await t.pumpAndSettle();
    expect(engine.loaded, ['hash4.mp3']);
    final queue = _player(t).queue;
    expect([for (final e in queue.entries) e.trackId], [3, 4, 1]);
    expect(queue.index, 1);
    expect(queue.source, const QueueSource.liked());
  });

  testWidgets('Play and Shuffle start the list with source liked', (t) async {
    await _open(t, _songs);
    await t.tap(find.text('Shuffle'));
    await t.pumpAndSettle();
    expect(_player(t).queue.shuffled, isTrue);
    expect(_player(t).queue.source, const QueueSource.liked());
  });

  testWidgets('Play and Shuffle are disabled when empty and the hint shows', (
    t,
  ) async {
    await _open(t, [_song(2, 'Backroads')]);
    expect(
      find.text('Songs you like appear here. Tap ♥ in the player to add one.'),
      findsOneWidget,
    );
    expect(find.text('0 songs · 0 min'), findsOneWidget);
    final buttons = t.widget<PlayShuffleButtons>(
      find.byType(PlayShuffleButtons),
    );
    expect(buttons.onPlay, isNull);
    expect(buttons.onShuffle, isNull);
  });

  testWidgets('unliking removes the song from the page', (t) async {
    final stream = StreamController<List<Track>>();
    addTearDown(stream.close);
    final songs = [
      _song(1, 'Amber Lights', likedAt: DateTime(2026, 11, 20)),
      _song(3, 'Coastline', likedAt: DateTime(2026, 11, 22)),
    ];
    stream.add(songs);
    await _open(t, const [], songsStream: stream.stream);
    expect(find.text('Amber Lights'), findsOneWidget);
    expect(find.text('Coastline'), findsOneWidget);

    stream.add([_song(1, 'Amber Lights'), songs[1]]);
    await t.pumpAndSettle();
    expect(find.text('Amber Lights'), findsNothing);
    expect(find.text('Coastline'), findsOneWidget);
    expect(find.text('1 song · 4 min'), findsOneWidget);
  });

  testWidgets('the page has no "…" button', (t) async {
    await _open(t, _songs);
    expect(find.byKey(const Key('detail-more')), findsNothing);
  });

  testWidgets('LikedArtwork shows a heart', (t) async {
    await _open(t, _songs);
    expect(
      find.descendant(
        of: find.byType(LikedArtwork),
        matching: find.byIcon(CupertinoIcons.heart_fill),
      ),
      findsOneWidget,
    );
  });
}
