import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/up_next.dart';

import '../support/fakes.dart';

final _upNext = find.byType(UpNext);

Finder _inQueue(Finder f) => find.descendant(of: _upNext, matching: f);

PlayerState _state(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(OwntuneApp)))
        .read(playerProvider);

List<int> _ids(WidgetTester t) => [
  for (final e in _state(t).queue.entries) e.trackId,
];

final _songs = [
  track(1, title: 'A song', artist: 'Juno Vale'),
  track(2, title: 'B song', artist: 'Juno Vale'),
  track(3, title: 'C song', artist: 'The Quiet Coast'),
  track(4, title: 'D song', artist: 'Lumen Kids'),
];

Future<void> _tall(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Plays [title] from the Songs list, opens the player and Up Next.
Future<void> _openQueue(WidgetTester t, String title) async {
  await t.tap(find.text(title));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('mini-player')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('player-up-next')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Up Next lists the upcoming songs with their source', (t) async {
    await _tall(t);
    await pumpApp(t, songs: _songs);
    await openLibraryTab(t);
    await _openQueue(t, 'B song');

    expect(_inQueue(find.text('Up Next')), findsOneWidget);
    expect(_inQueue(find.text('Playing from Songs')), findsOneWidget);
    expect(_inQueue(find.text('A song')), findsNothing);
    expect(
      t.getTopLeft(_inQueue(find.text('C song'))).dy,
      lessThan(t.getTopLeft(_inQueue(find.text('D song'))).dy),
    );
    // The current song shows in the compact row above the list.
    expect(
      find.descendant(
        of: find.byKey(const Key('player-sheet')),
        matching: find.text('B song'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('dragging the grip reorders', (t) async {
    await _tall(t);
    await pumpApp(t, songs: _songs);
    await openLibraryTab(t);
    await _openQueue(t, 'A song');

    final grip = find.descendant(
      of: find.byKey(const ValueKey('up-next-row-1')),
      matching: find.byIcon(CupertinoIcons.line_horizontal_3),
    );
    final rowHeight = t
        .getSize(find.byKey(const ValueKey('up-next-row-1')))
        .height;
    final gesture = await t.startGesture(t.getCenter(grip));
    await t.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, rowHeight * 0.25));
      await t.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await t.pumpAndSettle();

    expect(_ids(t), [1, 3, 4, 2]);
  });

  testWidgets('swiping left removes the song', (t) async {
    await _tall(t);
    await pumpApp(t, songs: _songs);
    await openLibraryTab(t);
    await _openQueue(t, 'A song');

    await t.drag(_inQueue(find.text('C song')), const Offset(-600, 0));
    await t.pumpAndSettle();

    expect(_ids(t), [1, 2, 4]);
    expect(_inQueue(find.text('C song')), findsNothing);
  });

  testWidgets('Clear keeps the current song playing', (t) async {
    final engine = FakeAudioEngine();
    await _tall(t);
    await pumpApp(t, songs: _songs, engine: engine);
    await openLibraryTab(t);
    await _openQueue(t, 'B song');

    await t.tap(find.byKey(const Key('up-next-clear')));
    await t.pumpAndSettle();

    expect(_ids(t), [1, 2]);
    expect(_state(t).queue.upcoming, isEmpty);
    expect(_state(t).queue.current!.trackId, 2);
    expect(engine.playing, isTrue);
    expect(_inQueue(find.text('C song')), findsNothing);
  });

  testWidgets('tapping an upcoming song plays it', (t) async {
    final engine = FakeAudioEngine();
    await _tall(t);
    await pumpApp(t, songs: _songs, engine: engine);
    await openLibraryTab(t);
    await _openQueue(t, 'A song');

    await t.tap(_inQueue(find.text('C song')));
    await t.pumpAndSettle();

    expect(engine.current, 'hash3.mp3');
    expect(_state(t).queue.current!.trackId, 3);
    expect(_inQueue(find.text('D song')), findsOneWidget);
  });

  testWidgets('Up Next with no source shows no "Playing from" line', (t) async {
    await _tall(t);
    await pumpApp(
      t,
      songs: _songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    await t.longPress(find.text('A song'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-play-next')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('mini-player')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('player-up-next')));
    await t.pumpAndSettle();

    expect(_inQueue(find.text('Up Next')), findsOneWidget);
    expect(_inQueue(find.textContaining('Playing from')), findsNothing);
  });

  testWidgets('the pill switches back to the cover', (t) async {
    await _tall(t);
    await pumpApp(t, songs: _songs);
    await openLibraryTab(t);
    await _openQueue(t, 'A song');
    expect(_upNext, findsOneWidget);

    await t.tap(find.byKey(const Key('player-up-next')));
    await t.pumpAndSettle();
    expect(_upNext, findsNothing);
  });
}
