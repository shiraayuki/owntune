import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/album_screen.dart';

import '../support/fakes.dart';

Track _lantern(
  int id,
  String title,
  int n, {
  String artist = 'Juno Vale',
  int? disc,
  int ms = 1000,
}) => track(
  id,
  title: title,
  artist: artist,
  albumArtist: 'Juno Vale',
  album: 'Paper Lanterns',
  trackNumber: n,
  discNumber: disc,
  durationMs: ms,
  year: 2021,
  genre: 'Indie Folk',
);

final _album = [
  _lantern(2, 'After the Rain', 2, ms: 222000),
  _lantern(1, 'Paper Lanterns', 1, ms: 251000),
  _lantern(4, 'Small Hours', 4, artist: 'Mira Sol', ms: 270000),
  _lantern(3, 'Kites Over Harbor', 3, ms: 235000),
];

Future<void> _open(WidgetTester t, {String album = 'Paper Lanterns'}) async {
  // Tall enough that every track row is built.
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.tap(find.text('Albums'));
  await t.pumpAndSettle();
  await t.tap(find.text(album));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('hero, meta line and tracks in order with durations', (t) async {
    await pumpApp(t, songs: _album);
    await _open(t);

    expect(find.text('Indie Folk · 2021'), findsOneWidget);
    expect(find.text('Juno Vale'), findsOneWidget);
    final rows = ['Paper Lanterns', 'After the Rain', 'Kites Over Harbor'];
    // The title "Paper Lanterns" is both the hero and the first track.
    expect(find.text('Paper Lanterns'), findsNWidgets(2));
    expect(
      t.getTopLeft(find.text(rows[1])).dy,
      lessThan(t.getTopLeft(find.text(rows[2])).dy),
    );
    expect(find.text('4:11'), findsOneWidget);
    expect(find.text('3:42'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    // Only the track by another artist shows its artist.
    expect(find.text('Mira Sol'), findsOneWidget);
    expect(find.text('Disc 1'), findsNothing);
  });

  testWidgets('meta line with only a year, and none without either', (t) async {
    await pumpApp(
      t,
      songs: [
        track(1, title: 'a', album: 'Yearly', year: 1999),
        track(2, title: 'b', album: 'Bare'),
      ],
    );
    await _open(t, album: 'Yearly');
    expect(find.text('1999'), findsOneWidget);
    await tapBack(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Bare'));
    await t.pumpAndSettle();
    expect(find.textContaining('·'), findsNothing);
  });

  testWidgets('disc headers only with more than one disc', (t) async {
    await pumpApp(
      t,
      songs: [_lantern(1, 'One', 1, disc: 1), _lantern(2, 'Two', 1, disc: 2)],
    );
    await _open(t);
    expect(find.text('Disc 1'), findsOneWidget);
    expect(find.text('Disc 2'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('Disc 2')).dy,
      greaterThan(t.getTopLeft(find.text('One')).dy),
    );
  });

  testWidgets('Play and Shuffle are active', (t) async {
    await pumpApp(t, songs: _album);
    await _open(t);
    PillButton button(String label) => t.widget<PillButton>(
      find.ancestor(of: find.text(label), matching: find.byType(PillButton)),
    );
    expect(button('Play').onPressed, isNotNull);
    expect(button('Shuffle').onPressed, isNotNull);
  });

  testWidgets('back returns to the albums tab', (t) async {
    await pumpApp(t, songs: _album);
    await _open(t);
    await tapBack(t);
    await t.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsNothing);
  });

  testWidgets('deleting the last track pops the album screen', (t) async {
    final tracks = StreamController<List<Track>>();
    addTearDown(tracks.close);
    tracks.add([..._album, track(9, title: 'Other', album: 'Ember')]);
    await pumpApp(t, songsStream: tracks.stream);
    await _open(t);
    expect(find.byType(AlbumScreen), findsOneWidget);

    tracks.add([track(9, title: 'Other', album: 'Ember')]);
    await t.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsNothing);
    expect(t.takeException(), isNull);
    expect(find.text('Ember'), findsOneWidget);
  });

  testWidgets('a track added during an import appears on the open album', (
    t,
  ) async {
    final tracks = StreamController<List<Track>>();
    addTearDown(tracks.close);
    tracks.add(_album);
    await pumpApp(t, songsStream: tracks.stream);
    await _open(t);
    expect(find.text('Late Arrival'), findsNothing);

    tracks.add([..._album, _lantern(5, 'Late Arrival', 5)]);
    await t.pumpAndSettle();
    expect(find.text('Late Arrival'), findsOneWidget);
  });

  testWidgets('album Edit Info edits all its songs', (t) async {
    await pumpApp(t, songs: _album);
    await _open(t);
    await t.tap(find.byKey(const Key('detail-more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-edit')));
    await t.pumpAndSettle();
    expect(find.text('Edit Info'), findsOneWidget);
    expect(find.text('4 Songs'), findsOneWidget);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('edit-field-album')))
          .controller!
          .text,
      'Paper Lanterns',
    );
  });

  testWidgets('renaming the album keeps its page open', (t) async {
    final library = StreamController<List<Track>>();
    addTearDown(library.close);
    await pumpApp(t, songsStream: library.stream);
    library.add(_album);
    await t.pumpAndSettle();
    await _open(t);
    expect(find.byType(AlbumScreen), findsOneWidget);

    library.add([
      for (final s in _album) s.copyWith(album: const Value('Lanterns')),
    ]);
    await t.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(find.text('Lanterns'), findsWidgets);
    expect(find.text('After the Rain'), findsOneWidget);
  });

  testWidgets('tapping the "…" on an album track opens the song menu', (
    t,
  ) async {
    await pumpApp(
      t,
      songs: _album,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await _open(t);
    await t.tap(find.byKey(const Key('song-more-1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu-play-next')), findsOneWidget);
    // Already on the album: no Go to Album.
    expect(find.text('Go to Album'), findsNothing);
    expect(find.text('Go to Artist'), findsOneWidget);
  });

  testWidgets('long-press on an album track still opens the menu', (t) async {
    await pumpApp(
      t,
      songs: _album,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await _open(t);
    await t.longPress(find.text('After the Rain'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu-play-next')), findsOneWidget);
  });
}
