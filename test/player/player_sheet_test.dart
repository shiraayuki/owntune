import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/player/play_queue.dart';
import 'package:owntune/player/player_controller.dart';

import '../support/fakes.dart';

final _sheet = find.byKey(const Key('player-sheet'));
final _mini = find.byKey(const Key('mini-player'));

PlayerState _state(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(OwntuneApp)))
        .read(playerProvider);

final _songs = [
  track(
    1,
    title: 'After the Rain',
    artist: 'Juno Vale',
    album: 'Paper Lanterns',
    trackNumber: 1,
    durationMs: 200000,
  ),
  track(2, title: 'Blue Hour', artist: 'The Quiet Coast'),
];

/// Plays [title] from the Songs list and opens the player.
Future<void> _open(WidgetTester t, String title) async {
  await t.tap(find.text(title));
  await t.pumpAndSettle();
  await t.tap(_mini);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('tapping the mini player opens the player', (t) async {
    await pumpApp(t, songs: _songs);
    await _open(t, 'After the Rain');

    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(
        of: _sheet,
        matching: find.text('Juno Vale · Paper Lanterns'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the top row sits below the status bar', (t) async {
    t.view.devicePixelRatio = 3;
    t.view.padding = const FakeViewPadding(top: 141);
    t.view.viewPadding = const FakeViewPadding(top: 141);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPadding);
    addTearDown(t.view.resetViewPadding);
    await pumpApp(t, songs: _songs);
    await _open(t, 'After the Rain');

    expect(
      t.getTopLeft(find.byKey(const Key('player-close'))).dy,
      greaterThanOrEqualTo(47),
    );
  });

  testWidgets('swiping down closes the player', (t) async {
    await pumpApp(t, songs: _songs);
    await _open(t, 'After the Rain');

    await t.fling(_sheet, const Offset(0, 600), 2000);
    await t.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(_mini, findsOneWidget);
  });

  testWidgets('the down arrow at the top left closes the player', (t) async {
    await pumpApp(t, songs: _songs);
    await _open(t, 'After the Rain');

    final close = find.byKey(const Key('player-close'));
    expect(
      find.descendant(
        of: close,
        matching: find.byIcon(CupertinoIcons.chevron_down),
      ),
      findsOneWidget,
    );
    final sheetBox = t.getRect(_sheet);
    expect(t.getCenter(close).dx, lessThan(sheetBox.center.dx));

    await t.tap(close);
    await t.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(_mini, findsOneWidget);
  });

  testWidgets('the menu button sits at the top right, once', (t) async {
    await pumpApp(t, songs: _songs);
    await _open(t, 'After the Rain');

    final more = find.byKey(const Key('player-more'));
    expect(more, findsOneWidget);
    final close = find.byKey(const Key('player-close'));
    expect(t.getCenter(more).dx, greaterThan(t.getRect(_sheet).center.dx));
    expect(t.getCenter(more).dy, closeTo(t.getCenter(close).dy, 1));
    // Above the title, not next to it.
    expect(
      t.getCenter(more).dy,
      lessThan(
        t
            .getTopLeft(
              find.descendant(
                of: _sheet,
                matching: find.text('After the Rain'),
              ),
            )
            .dy,
      ),
    );

    await t.tap(find.byKey(const Key('player-up-next')));
    await t.pumpAndSettle();
    expect(more, findsOneWidget);
  });

  testWidgets('play and next work in the player', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _songs, engine: engine);
    await _open(t, 'After the Rain');

    await t.tap(find.byKey(const Key('player-play')));
    await t.pumpAndSettle();
    expect(engine.playing, isFalse);
    await t.tap(find.byKey(const Key('player-next')));
    await t.pumpAndSettle();
    expect(engine.current, 'hash2.mp3');
    expect(
      find.descendant(of: _sheet, matching: find.text('Blue Hour')),
      findsOneWidget,
    );
  });

  testWidgets('repeat cycles off, all, one', (t) async {
    await pumpApp(t, songs: _songs);
    await _open(t, 'After the Rain');
    final repeat = find.byKey(const Key('player-repeat'));
    Finder icon(IconData i) =>
        find.descendant(of: repeat, matching: find.byIcon(i));

    expect(_state(t).queue.repeat, QueueRepeat.off);
    await t.tap(repeat);
    await t.pumpAndSettle();
    expect(_state(t).queue.repeat, QueueRepeat.all);
    expect(icon(CupertinoIcons.repeat), findsOneWidget);
    await t.tap(repeat);
    await t.pumpAndSettle();
    expect(_state(t).queue.repeat, QueueRepeat.one);
    expect(icon(CupertinoIcons.repeat_1), findsOneWidget);
    await t.tap(repeat);
    await t.pumpAndSettle();
    expect(_state(t).queue.repeat, QueueRepeat.off);
  });

  testWidgets('shuffle toggles in Now Playing', (t) async {
    await pumpApp(t, songs: _songs);
    await _open(t, 'After the Rain');
    final shuffle = find.byKey(const Key('player-shuffle'));

    expect(_state(t).queue.shuffled, isFalse);
    await t.tap(shuffle);
    await t.pumpAndSettle();
    expect(_state(t).queue.shuffled, isTrue);
    expect(_state(t).queue.current!.trackId, 1);
    await t.tap(shuffle);
    await t.pumpAndSettle();
    expect(_state(t).queue.shuffled, isFalse);
  });

  testWidgets('scrubbing seeks on release only', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _songs, engine: engine);
    await _open(t, 'After the Rain');

    final scrubber = find.byKey(const Key('scrubber'));
    final gesture = await t.startGesture(t.getCenter(scrubber));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(-30, 0));
    await t.pump();
    // The labels follow the finger: half of 3:20.
    expect(
      find.descendant(of: _sheet, matching: find.text('1:40')),
      findsOneWidget,
    );
    expect(engine.lastSeek, isNull);

    await gesture.up();
    await t.pumpAndSettle();
    expect(engine.lastSeek!.inMilliseconds, closeTo(100000, 2000));
  });

  testWidgets('the times show elapsed and remaining', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _songs, engine: engine);
    await _open(t, 'After the Rain');

    engine.emitPosition(const Duration(seconds: 84));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: _sheet, matching: find.text('1:24')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _sheet, matching: find.text('-1:56')),
      findsOneWidget,
    );
  });

  testWidgets('the player closes when its only song is deleted', (t) async {
    final library = StreamController<List<Track>>();
    addTearDown(library.close);
    await pumpApp(t, songsStream: library.stream);
    library.add([_songs.first]);
    await t.pumpAndSettle();
    await _open(t, 'After the Rain');
    expect(_sheet, findsOneWidget);

    library.add([]);
    await t.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(_mini, findsNothing);
  });

  testWidgets('Go to Album from the player closes it and opens the album', (
    t,
  ) async {
    await pumpApp(
      t,
      songs: _songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await _open(t, 'After the Rain');

    await t.tap(find.byKey(const Key('player-more')));
    await t.pumpAndSettle();
    expect(find.text('Play Next'), findsNothing);
    await t.tap(find.text('Go to Album'));
    await t.pumpAndSettle();

    expect(_sheet, findsNothing);
    expect(find.byType(AlbumScreen), findsOneWidget);
  });

  testWidgets('a notice shows on top of the open player', (t) async {
    final engine = FakeAudioEngine()..failing.add('hash2.mp3');
    await pumpApp(
      t,
      songs: [
        ..._songs,
        track(3, title: 'Cassette Summer'),
      ],
      engine: engine,
    );
    await _open(t, 'After the Rain');

    await t.tap(find.byKey(const Key('player-next')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));

    final notice = find.text("Couldn't play “Blue Hour”");
    expect(notice, findsOneWidget);
    // Outside the navigator, so it is painted above every route, including
    // the full-screen player.
    expect(
      find.descendant(of: find.byType(Navigator), matching: notice),
      findsNothing,
    );
    expect(_sheet, findsOneWidget);
  });
}
