import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/artist_screen.dart';
import 'package:owntune/library/artists_screen.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/navigation.dart';

import '../support/fakes.dart';

void main() {
  final songs = [
    track(1, title: 'a', artist: 'The Quiet Coast', album: 'Low Tide Radio'),
    track(2, title: 'b', artist: 'Neon Harbor', album: 'Velvet Hours'),
    track(3, title: 'c', artist: 'Neon Harbor', album: 'Midnight Static'),
    track(4, title: 'd', artist: 'Neon Harbor', album: 'Midnight Static'),
    track(5, originalName: 'demo_3.wav'),
  ];

  test('artistCounts', () {
    final lib = Library.from([
      ...songs,
      track(6, title: 'e', artist: 'Lumen Kids'),
    ]);
    String counts(String name) =>
        artistCounts(lib.artist(artistGroupKey(name))!);
    expect(counts('Neon Harbor'), '2 albums · 3 songs');
    expect(counts('The Quiet Coast'), '1 album · 1 song');
    expect(counts('Lumen Kids'), '1 song');
  });

  testWidgets('lists artists by name with counts and a chevron', (t) async {
    await pumpApp(t, songs: songs);
    await t.tap(find.text('Artists'));
    await t.pumpAndSettle();
    final names = ['Neon Harbor', 'The Quiet Coast', 'Unknown Artist'];
    for (var i = 0; i + 1 < names.length; i++) {
      expect(
        t.getTopLeft(find.text(names[i])).dy,
        lessThan(t.getTopLeft(find.text(names[i + 1])).dy),
      );
    }
    expect(find.text('2 albums · 3 songs'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.chevron_right), findsNWidgets(3));
  });

  testWidgets('emptied library shows the empty state, no sub-tabs', (t) async {
    final songs = StreamController<List<Track>>();
    addTearDown(songs.close);
    await pumpApp(t, songsStream: songs.stream);
    songs.add([track(1, title: 'x', artist: 'Y', album: 'Z')]);
    await t.pumpAndSettle();
    await t.tap(find.text('Artists'));
    await t.pumpAndSettle();

    songs.add([]);
    await t.pumpAndSettle();
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-segments')), findsNothing);
  });

  testWidgets('tapping an artist opens it with back label Artists', (t) async {
    await pumpApp(t, songs: songs);
    await t.tap(find.text('Artists'));
    await t.pumpAndSettle();
    await t.tap(find.text('Neon Harbor'));
    await t.pumpAndSettle();
    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(NavRow), matching: find.text('Artists')),
      findsOneWidget,
    );
  });
}
