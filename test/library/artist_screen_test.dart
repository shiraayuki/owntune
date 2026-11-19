import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/artist_screen.dart';
import 'package:owntune/library/navigation.dart';

import '../support/fakes.dart';

final _neon = [
  track(
    1,
    title: 'Amber Lights',
    artist: 'Neon Harbor',
    album: 'Velvet Hours',
    year: 2021,
  ),
  track(
    2,
    title: 'Broken Neon',
    artist: 'Neon Harbor',
    album: 'Midnight Static',
    year: 2023,
  ),
  track(
    3,
    title: 'City Breathing',
    artist: 'Neon Harbor',
    album: 'Midnight Static',
    year: 2023,
  ),
  track(
    4,
    title: 'Dial Tone',
    artist: 'Neon Harbor',
    album: 'Midnight Static',
    year: 2023,
  ),
  track(
    5,
    title: 'Echo Park',
    artist: 'Neon Harbor',
    album: 'Velvet Hours',
    year: 2021,
  ),
];

Future<void> _open(WidgetTester t, String artist) async {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.tap(find.text('Artists'));
  await t.pumpAndSettle();
  await t.tap(find.text(artist));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('counts, albums by year and five songs without See All', (
    t,
  ) async {
    await pumpApp(t, songs: _neon);
    await _open(t, 'Neon Harbor');

    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(find.text('2 albums · 5 songs'), findsOneWidget);
    expect(find.text('2023'), findsOneWidget);
    expect(find.text('2021'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('2023')).dx,
      lessThan(t.getTopLeft(find.text('2021')).dx),
    );
    for (final s in _neon) {
      expect(find.text(s.title!), findsOneWidget);
    }
    // Song rows show only the album as subtitle.
    expect(find.text('Velvet Hours'), findsNWidgets(3)); // card + 2 rows
    expect(find.text('Neon Harbor · Velvet Hours'), findsNothing);
    expect(find.text('See All'), findsNothing);
  });

  testWidgets('See All lists every song with the artist as title', (t) async {
    final six = [
      ..._neon,
      track(6, title: 'Faded', artist: 'Neon Harbor', album: 'Velvet Hours'),
    ];
    await pumpApp(t, songs: six);
    await _open(t, 'Neon Harbor');
    expect(find.text('Faded'), findsNothing);

    await t.tap(find.text('See All'));
    await t.pumpAndSettle();
    expect(find.byType(ArtistSongsScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavRow),
        matching: find.text('Neon Harbor'),
      ),
      findsOneWidget,
    );
    for (final s in six) {
      expect(find.text(s.title!), findsOneWidget);
    }
  });

  testWidgets('no Albums section for an artist without albums', (t) async {
    await pumpApp(
      t,
      songs: [
        track(
          1,
          title: 'Cassette Summer',
          artist: 'Lumen Kids',
          album: 'Summer',
          albumArtist: 'Various Artists',
        ),
      ],
    );
    await _open(t, 'Lumen Kids');
    expect(find.text('1 song'), findsOneWidget);
    expect(find.text('Albums'), findsNothing);
    expect(find.text('Songs'), findsOneWidget);
  });

  testWidgets('Play and Shuffle are shown but disabled', (t) async {
    await pumpApp(t, songs: _neon);
    await _open(t, 'Neon Harbor');
    for (final label in ['Play', 'Shuffle']) {
      final button = t.widget<PillButton>(
        find.ancestor(of: find.text(label), matching: find.byType(PillButton)),
      );
      expect(button.onPressed, isNull, reason: label);
    }
  });

  testWidgets('deleting the artist\'s last song pops the artist screen', (
    t,
  ) async {
    final other = track(9, title: 'Other', artist: 'Juno Vale');
    final tracks = StreamController<List<Track>>();
    addTearDown(tracks.close);
    tracks.add([..._neon, other]);
    await pumpApp(t, songsStream: tracks.stream);
    await _open(t, 'Neon Harbor');

    tracks.add([other]);
    await t.pumpAndSettle();
    expect(find.byType(ArtistScreen), findsNothing);
    expect(t.takeException(), isNull);
    expect(find.text('Juno Vale'), findsOneWidget);
  });

  testWidgets('an album opened from an artist keeps the artist as back label', (
    t,
  ) async {
    await pumpApp(t, songs: _neon);
    await _open(t, 'Neon Harbor');
    // The album card's title comes first; song rows repeat it as subtitle.
    await t.tap(find.text('Velvet Hours').first);
    await t.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavRow),
        matching: find.text('Neon Harbor'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(NavRow), matching: find.text('Library')),
      findsNothing,
    );
  });
}
