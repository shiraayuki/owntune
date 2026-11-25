import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/library/songs_screen.dart';

import '../support/fakes.dart';

final _mini = find.byKey(const Key('mini-player'));

Finder _inMini(Finder f) => find.descendant(of: _mini, matching: f);

final _abc = [
  track(1, title: 'A song', artist: 'Juno Vale'),
  track(2, title: 'B song', artist: 'Juno Vale'),
  track(3, title: 'C song', artist: 'Juno Vale'),
];

Future<void> _play(WidgetTester t, String title) async {
  await t.tap(find.text(title).first);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('mini player is hidden while nothing plays', (t) async {
    await pumpApp(t, songs: _abc);
    await openLibraryTab(t);
    expect(_mini, findsNothing);
  });

  testWidgets('shows title, artist and pauses in place', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _abc, engine: engine);
    await openLibraryTab(t);
    await _play(t, 'B song');

    expect(_inMini(find.text('B song')), findsOneWidget);
    expect(_inMini(find.text('Juno Vale')), findsOneWidget);
    expect(_inMini(find.byIcon(CupertinoIcons.pause_fill)), findsOneWidget);

    await t.tap(find.byKey(const Key('mini-play')));
    await t.pumpAndSettle();
    expect(engine.playing, isFalse);
    expect(_inMini(find.byIcon(CupertinoIcons.play_fill)), findsOneWidget);
  });

  testWidgets('mini player shows on the album screen without a tab bar', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pumpApp(
      t,
      songs: [
        track(1, title: 'First', album: 'Paper Lanterns', trackNumber: 1),
      ],
    );
    await openLibraryTab(t);
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    await t.tap(find.text('Paper Lanterns'));
    await t.pumpAndSettle();
    await t.tap(find.text('First'));
    await t.pumpAndSettle();

    expect(_mini, findsOneWidget);
    expect(find.text('Playlists'), findsNothing);
    final screen = t.view.physicalSize / t.view.devicePixelRatio;
    final bottomInset = t.view.viewPadding.bottom / t.view.devicePixelRatio;
    expect(
      t.getBottomLeft(_mini).dy,
      closeTo(screen.height - bottomInset - 8, 1),
    );
  });

  testWidgets('zero duration draws an empty progress line', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(
      t,
      songs: [track(1, title: 'Silent', durationMs: 0)],
      engine: engine,
    );
    await openLibraryTab(t);
    await _play(t, 'Silent');
    engine.emitPosition(const Duration(seconds: 5));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    final bar = t.widget<FractionallySizedBox>(
      _inMini(find.byType(FractionallySizedBox)),
    );
    expect(bar.widthFactor, 0);
  });

  testWidgets('progress follows the position', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(
      t,
      songs: [track(1, title: 'Long', durationMs: 200000)],
      engine: engine,
    );
    await openLibraryTab(t);
    await _play(t, 'Long');
    engine.emitPosition(const Duration(seconds: 50));
    await t.pumpAndSettle();

    final bar = t.widget<FractionallySizedBox>(
      _inMini(find.byType(FractionallySizedBox)),
    );
    expect(bar.widthFactor, closeTo(0.25, 0.001));
  });

  testWidgets('the last song row can scroll above the mini player', (t) async {
    final songs = [
      for (var i = 1; i <= 30; i++) track(i, title: 'Song ${i + 100}'),
    ];
    await pumpApp(t, songs: songs);
    await openLibraryTab(t);
    await _play(t, 'Song 101');

    await t.fling(find.byType(SongList), const Offset(0, -5000), 3000);
    await t.pumpAndSettle();

    final last = find.text('Song 130');
    expect(last, findsOneWidget);
    expect(t.getBottomLeft(last).dy, lessThanOrEqualTo(t.getTopLeft(_mini).dy));
  });

  testWidgets('the mini player has a heart and play/pause', (t) async {
    await pumpApp(t, songs: _abc);
    await openLibraryTab(t);
    await _play(t, 'A song');
    expect(find.byKey(const Key('mini-play')), findsOneWidget);
    expect(find.byKey(const Key('mini-like')), findsOneWidget);
    expect(_inMini(find.byType(IconButton)), findsNWidgets(2));
    expect(
      t.getCenter(find.byKey(const Key('mini-like'))).dx,
      lessThan(t.getCenter(find.byKey(const Key('mini-play'))).dx),
    );
    expect(_inMini(find.byIcon(CupertinoIcons.forward_fill)), findsNothing);
  });

  testWidgets('the mini player heart likes the song without opening the '
      'player', (t) async {
    final repo = FakeTrackRepository();
    await pumpApp(
      t,
      songs: _abc,
      overrides: [trackRepositoryProvider.overrideWithValue(repo)],
    );
    await openLibraryTab(t);
    await _play(t, 'B song');

    final like = find.byKey(const Key('mini-like'));
    expect(
      find.descendant(of: like, matching: find.byIcon(CupertinoIcons.heart)),
      findsOneWidget,
    );
    await t.tap(like);
    await t.pumpAndSettle();
    expect(repo.likeCalls.map((c) => (c.ids.single, c.liked)), [(2, true)]);
    expect(find.byKey(const Key('player-sheet')), findsNothing);
  });

  testWidgets('a failed like from the mini player shows a dialog', (t) async {
    await pumpApp(
      t,
      songs: _abc,
      overrides: [
        trackRepositoryProvider.overrideWithValue(_FailingLikeRepository()),
      ],
    );
    await openLibraryTab(t);
    await _play(t, 'A song');

    await t.tap(find.byKey(const Key('mini-like')));
    await t.pumpAndSettle();
    expect(find.text('Could not update Liked Songs'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
  });

  testWidgets('a liked song shows a filled accent heart in the mini player', (
    t,
  ) async {
    final repo = FakeTrackRepository();
    await pumpApp(
      t,
      songs: [track(1, title: 'A song', likedAt: DateTime(2026, 11, 24))],
      overrides: [trackRepositoryProvider.overrideWithValue(repo)],
    );
    await openLibraryTab(t);
    await _play(t, 'A song');

    final like = find.byKey(const Key('mini-like'));
    final icon = t.widget<Icon>(
      find.descendant(of: like, matching: find.byType(Icon)),
    );
    expect(icon.icon, CupertinoIcons.heart_fill);
    expect(
      icon.color,
      Theme.of(t.element(like)).extension<OwntuneColors>()!.accent,
    );
    await t.tap(like);
    await t.pump();
    expect(repo.likeCalls.map((c) => (c.ids.single, c.liked)), [(1, false)]);
  });

  testWidgets('swiping left goes to the next song', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _abc, engine: engine);
    await openLibraryTab(t);
    await _play(t, 'A song');

    await t.drag(_mini, const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(engine.current, 'hash2.mp3');
    expect(_inMini(find.text('B song')), findsOneWidget);
  });

  testWidgets('swiping right goes to the previous song even late in it', (
    t,
  ) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _abc, engine: engine);
    await openLibraryTab(t);
    await _play(t, 'B song');
    engine.emitPosition(const Duration(seconds: 30));
    await t.pump();

    await t.drag(_mini, const Offset(300, 0));
    await t.pumpAndSettle();
    expect(engine.current, 'hash1.mp3');
  });

  testWidgets('swiping right on the first song restarts it', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _abc, engine: engine);
    await openLibraryTab(t);
    await _play(t, 'A song');

    await t.drag(_mini, const Offset(300, 0));
    await t.pumpAndSettle();
    expect(engine.loaded, ['hash1.mp3']);
    expect(engine.lastSeek, Duration.zero);
  });

  testWidgets('swiping left on the last song with repeat off does nothing', (
    t,
  ) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _abc, engine: engine);
    await openLibraryTab(t);
    await _play(t, 'C song');

    await t.drag(_mini, const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(engine.loaded, ['hash3.mp3']);
  });

  testWidgets('a short slow swipe does nothing', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _abc, engine: engine);
    await openLibraryTab(t);
    await _play(t, 'A song');

    final gesture = await t.startGesture(t.getCenter(_mini));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-5, 0));
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await t.pumpAndSettle();
    expect(engine.loaded, ['hash1.mp3']);
  });
}

class _FailingLikeRepository extends FakeTrackRepository {
  @override
  Future<void> setLiked(Iterable<int> ids, {required bool liked}) async =>
      throw StateError('disk full');
}
