import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/songs_screen.dart';
import 'package:owntune/player/player_controller.dart';

import '../support/fakes.dart';

// OwntuneApp sits above the navigator, so it is onstage on every screen.
PlayerState _state(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(OwntuneApp)))
        .read(playerProvider);

List<int> _ids(WidgetTester t) => [
  for (final e in _state(t).queue.entries) e.trackId,
];

Future<void> _tall(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

final _abc = [
  track(1, title: 'A song'),
  track(2, title: 'B song'),
  track(3, title: 'C song'),
];

Track _album(int id, String title, int n) => track(
  id,
  title: title,
  artist: 'Juno Vale',
  album: 'Paper Lanterns',
  trackNumber: n,
);

void main() {
  testWidgets('tapping a song plays it with the list as the queue', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _abc, engine: engine);

    await t.tap(find.text('B song'));
    await t.pumpAndSettle();

    expect(engine.loaded, ['hash2.mp3']);
    expect(engine.playing, isTrue);
    expect(_ids(t), [1, 2, 3]);
    expect(_state(t).queue.index, 1);
    expect(_state(t).queue.source, 'Songs');
  });

  testWidgets('tapping a filtered song queues only the matches', (t) async {
    await pumpApp(
      t,
      songs: [
        track(1, title: 'Amber'),
        track(2, title: 'Blue Hour'),
        track(3, title: 'Blueberry'),
      ],
    );
    await t.enterText(
      find.descendant(
        of: find.byType(SongsScreen),
        matching: find.byType(TextField),
      ),
      'blue',
    );
    await t.pumpAndSettle();

    await t.tap(find.text('Blueberry'));
    await t.pumpAndSettle();

    expect(_ids(t), [2, 3]);
    expect(_state(t).queue.current!.trackId, 3);
  });

  testWidgets('album Play starts at the first track', (t) async {
    await _tall(t);
    final engine = FakeAudioEngine();
    await pumpApp(
      t,
      songs: [
        _album(7, 'Second', 2),
        _album(8, 'First', 1),
        _album(9, 'Third', 3),
      ],
      engine: engine,
    );
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    await t.tap(find.text('Paper Lanterns'));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(PillButton, 'Play'));
    await t.pumpAndSettle();

    expect(engine.loaded, ['hash8.mp3']);
    expect(_ids(t), [8, 7, 9]);
    expect(_state(t).queue.source, 'Paper Lanterns');
  });

  testWidgets('album Shuffle plays shuffled', (t) async {
    await _tall(t);
    await pumpApp(t, songs: [_album(1, 'First', 1), _album(2, 'Second', 2)]);
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    await t.tap(find.text('Paper Lanterns'));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(PillButton, 'Shuffle'));
    await t.pumpAndSettle();
    expect(_state(t).queue.shuffled, isTrue);
    expect(_state(t).playing, isTrue);
    expect([..._ids(t)]..sort(), [1, 2]);
    expect(_state(t).queue.source, 'Paper Lanterns');
  });

  testWidgets('album Play turns shuffle off', (t) async {
    await _tall(t);
    await pumpApp(t, songs: [_album(1, 'First', 1), _album(2, 'Second', 2)]);
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    await t.tap(find.text('Paper Lanterns'));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(PillButton, 'Shuffle'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(PillButton, 'Play'));
    await t.pumpAndSettle();
    expect(_state(t).queue.shuffled, isFalse);
    expect(_ids(t), [1, 2]);
    expect(_state(t).queue.index, 0);
  });

  testWidgets('artist Shuffle plays shuffled', (t) async {
    await _tall(t);
    final songs = [
      for (var i = 1; i <= 3; i++)
        track(i, title: 'Song $i', artist: 'Neon Harbor', album: 'Static'),
    ];
    await pumpApp(t, songs: songs);
    await t.tap(find.text('Artists'));
    await t.pumpAndSettle();
    await t.tap(find.text('Neon Harbor'));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(PillButton, 'Shuffle'));
    await t.pumpAndSettle();
    expect(_state(t).queue.shuffled, isTrue);
    expect([..._ids(t)]..sort(), [1, 2, 3]);
    expect(_state(t).queue.source, 'Neon Harbor');
  });

  testWidgets('tapping an album track plays the album from there', (t) async {
    await _tall(t);
    final engine = FakeAudioEngine();
    await pumpApp(
      t,
      songs: [_album(1, 'First', 1), _album(2, 'Second', 2)],
      engine: engine,
    );
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    await t.tap(find.text('Paper Lanterns'));
    await t.pumpAndSettle();

    await t.tap(find.text('Second'));
    await t.pumpAndSettle();

    expect(engine.loaded, ['hash2.mp3']);
    expect(_ids(t), [1, 2]);
  });

  testWidgets("a preview song on the artist page queues all the artist's "
      'songs', (t) async {
    await _tall(t);
    final songs = [
      for (var i = 1; i <= 8; i++)
        track(i, title: 'Song $i', artist: 'Neon Harbor', album: 'Static'),
    ];
    await pumpApp(t, songs: songs);
    await t.tap(find.text('Artists'));
    await t.pumpAndSettle();
    await t.tap(find.text('Neon Harbor'));
    await t.pumpAndSettle();

    final second = find.byType(SongRow).at(1);
    final tapped = t.widget<SongRow>(second).track.id;
    await t.tap(second);
    await t.pumpAndSettle();

    expect(_state(t).queue.entries, hasLength(8));
    expect(_state(t).queue.index, 1);
    expect(_state(t).queue.current!.trackId, tapped);
    expect(_state(t).queue.source, 'Neon Harbor');
  });

  testWidgets('artist Play plays all their songs from the first', (t) async {
    await _tall(t);
    final songs = [
      for (var i = 1; i <= 3; i++)
        track(i, title: 'Song $i', artist: 'Neon Harbor', album: 'Static'),
    ];
    await pumpApp(t, songs: songs);
    await t.tap(find.text('Artists'));
    await t.pumpAndSettle();
    await t.tap(find.text('Neon Harbor'));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(PillButton, 'Play'));
    await t.pumpAndSettle();

    expect(_state(t).queue.entries, hasLength(3));
    expect(_state(t).queue.index, 0);
    expect(_state(t).queue.shuffled, isFalse);
  });

  testWidgets('a song in Search plays with the search results as the queue', (
    t,
  ) async {
    await pumpApp(
      t,
      songs: [
        track(1, title: 'Night Drive'),
        track(2, title: 'Morning'),
        track(3, title: 'Night Swim'),
      ],
    );
    await t.tap(find.text('Search').last);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'night');
    await t.pumpAndSettle();

    await t.tap(find.text('Night Swim'));
    await t.pumpAndSettle();

    expect(_state(t).queue.source, 'Search');
    expect(_ids(t).toSet(), {1, 3});
    expect(_state(t).queue.current!.trackId, 3);
  });

  testWidgets('the playing song is tinted', (t) async {
    // Paper (light) is monochrome: its tint is the text color.
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(t, songs: _abc);
    await t.tap(find.text('B song'));
    await t.pumpAndSettle();

    // The mini player shows the title too.
    Finder inRow(String text) =>
        find.descendant(of: find.byType(SongRow), matching: find.text(text));
    final accent = Theme.of(t.element(find.byType(AppShell)))
        .extension<OwntuneColors>()!
        .accent;
    expect(t.widget<Text>(inRow('B song')).style!.color, accent);
    expect(t.widget<Text>(inRow('A song')).style!.color, isNot(accent));
  });

  testWidgets('the playing album track shows bars instead of its number', (
    t,
  ) async {
    await _tall(t);
    await pumpApp(t, songs: [_album(1, 'First', 1), _album(2, 'Second', 2)]);
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    await t.tap(find.text('Paper Lanterns'));
    await t.pumpAndSettle();
    await t.tap(find.text('Second'));
    await t.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('Second'),
      matching: find.byType(AlbumTrackRow),
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(CupertinoIcons.chart_bar_alt_fill),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: row, matching: find.text('2')), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('an unplayable song shows a notice', (t) async {
    final engine = FakeAudioEngine()..failing.add('hash2.mp3');
    await pumpApp(t, songs: _abc, engine: engine);

    await t.tap(find.text('B song'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));

    expect(find.text("Couldn't play “B song”"), findsOneWidget);
    expect(engine.current, 'hash3.mp3');
  });
}
