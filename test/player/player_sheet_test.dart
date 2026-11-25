import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/settings/settings.dart';
import 'package:owntune/player/cover_colors.dart';
import 'package:owntune/player/cover_tint.dart';
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
  _tintTests();

  testWidgets('tapping the mini player opens the player', (t) async {
    await pumpApp(t, songs: _songs);
    await openLibraryTab(t);
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
    await openLibraryTab(t);
    await _open(t, 'After the Rain');

    expect(
      t.getTopLeft(find.byKey(const Key('player-close'))).dy,
      greaterThanOrEqualTo(47),
    );
  });

  testWidgets('swiping down closes the player', (t) async {
    await pumpApp(t, songs: _songs);
    await openLibraryTab(t);
    await _open(t, 'After the Rain');

    await t.fling(_sheet, const Offset(0, 600), 2000);
    await t.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(_mini, findsOneWidget);
  });

  testWidgets('the down arrow at the top left closes the player', (t) async {
    await pumpApp(t, songs: _songs);
    await openLibraryTab(t);
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
    await openLibraryTab(t);
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
    await openLibraryTab(t);
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
    await openLibraryTab(t);
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
    await openLibraryTab(t);
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
    await openLibraryTab(t);
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
    await openLibraryTab(t);
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
    await openLibraryTab(t);
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
    await openLibraryTab(t);
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
    await openLibraryTab(t);
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

  testWidgets('heart shows the like state and toggles it', (t) async {
    final repo = FakeTrackRepository();
    await pumpApp(
      t,
      songs: _songs,
      overrides: [trackRepositoryProvider.overrideWithValue(repo)],
    );
    await openLibraryTab(t);
    await _open(t, 'After the Rain');

    final heart = find.descendant(
      of: find.byKey(const Key('player-like')),
      matching: find.byIcon(CupertinoIcons.heart),
    );
    expect(heart, findsOneWidget);
    await t.tap(find.byKey(const Key('player-like')));
    await t.pump();
    expect(repo.likeCalls.map((c) => (c.ids.single, c.liked)), [(1, true)]);
  });

  testWidgets('a liked song shows a filled accent heart and a tap unlikes', (
    t,
  ) async {
    final repo = FakeTrackRepository();
    await pumpApp(
      t,
      songs: [
        track(1, title: 'After the Rain', likedAt: DateTime(2026, 11, 24)),
      ],
      overrides: [trackRepositoryProvider.overrideWithValue(repo)],
    );
    await openLibraryTab(t);
    await _open(t, 'After the Rain');

    final like = find.byKey(const Key('player-like'));
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

  testWidgets('a failed like from the heart shows a dialog', (t) async {
    await pumpApp(
      t,
      songs: _songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(_FailingLikeRepository()),
      ],
    );
    await openLibraryTab(t);
    await _open(t, 'After the Rain');

    await t.tap(find.byKey(const Key('player-like')));
    await t.pumpAndSettle();
    expect(find.text('Could not update Liked Songs'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
  });

  testWidgets('the song menu in the player offers Add to Liked Songs', (
    t,
  ) async {
    final repo = FakeTrackRepository();
    await pumpApp(
      t,
      songs: _songs,
      overrides: [trackRepositoryProvider.overrideWithValue(repo)],
    );
    await openLibraryTab(t);
    await _open(t, 'After the Rain');

    await t.tap(find.byKey(const Key('player-more')));
    await t.pumpAndSettle();
    await t.tap(find.text('Add to Liked Songs'));
    await t.pumpAndSettle();
    expect(repo.likeCalls.map((c) => (c.ids.single, c.liked)), [(1, true)]);
  });

  group('swiping the cover', () {
    final cover = find.byKey(const Key('player-cover'));
    final nextCover = find.byKey(const Key('player-cover-next'));
    final songs = [
      for (var i = 1; i <= 5; i++)
        track(i, title: 'Song $i', artist: 'Artist $i', cover: 'c$i.jpg'),
    ];

    /// The cover file the neighbour [finder] shows.
    String? coverOf(WidgetTester t, Finder finder) => t
        .widget<Artwork>(
          find.descendant(of: finder, matching: find.byType(Artwork)),
        )
        .file
        ?.uri
        .pathSegments
        .last;

    Future<FakeAudioEngine> open(WidgetTester t, String title) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final engine = FakeAudioEngine();
      await pumpApp(t, songs: songs, engine: engine);
      await openLibraryTab(t);
      await _open(t, title);
      return engine;
    }

    testWidgets('left plays the next song', (t) async {
      final engine = await open(t, 'Song 2');
      await t.drag(cover, const Offset(-200, 0));
      await t.pumpAndSettle();
      expect(engine.current, 'hash3.mp3');
      expect(
        find.descendant(of: _sheet, matching: find.text('Song 3')),
        findsOneWidget,
      );
    });

    testWidgets('right goes to the previous song even late in it', (t) async {
      final engine = await open(t, 'Song 2');
      engine.emitPosition(const Duration(seconds: 30));
      await t.pump();
      await t.drag(cover, const Offset(200, 0));
      await t.pumpAndSettle();
      expect(engine.current, 'hash1.mp3');
    });

    testWidgets('right on the first song restarts it', (t) async {
      final engine = await open(t, 'Song 1');
      await t.drag(cover, const Offset(200, 0));
      await t.pumpAndSettle();
      expect(engine.loaded, ['hash1.mp3']);
      expect(engine.lastSeek, Duration.zero);
    });

    testWidgets('a short slow drag springs back', (t) async {
      final engine = await open(t, 'Song 2');
      final gesture = await t.startGesture(t.getCenter(cover));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(-5, 0));
        await t.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await t.pumpAndSettle();
      expect(engine.loaded, ['hash2.mp3']);
      expect(nextCover, findsNothing);
    });

    testWidgets('the next cover shows beside the cover while dragging', (
      t,
    ) async {
      await open(t, 'Song 2');
      expect(nextCover, findsNothing);
      final gesture = await t.startGesture(t.getCenter(cover));
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(const Offset(-60, 0));
      await t.pump();
      expect(coverOf(t, nextCover), 'c3.jpg');
      expect(
        t.getTopLeft(nextCover).dx,
        greaterThan(t.getTopRight(cover).dx - 100),
      );
      await gesture.up();
      await t.pumpAndSettle();
    });

    testWidgets('with shuffle on the next cover is the next in play order', (
      t,
    ) async {
      final engine = await open(t, 'Song 1');
      await t.tap(find.byKey(const Key('player-shuffle')));
      await t.pumpAndSettle();
      final q = _state(t).queue;
      final upcoming = q.entries[q.index + 1].trackId;

      final gesture = await t.startGesture(t.getCenter(cover));
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(const Offset(-60, 0));
      await t.pump();
      expect(coverOf(t, nextCover), 'c$upcoming.jpg');
      await gesture.moveBy(const Offset(-150, 0));
      await gesture.up();
      await t.pumpAndSettle();
      expect(engine.current, 'hash$upcoming.mp3');
    });

    testWidgets('on the last song with repeat off left does nothing', (
      t,
    ) async {
      final engine = await open(t, 'Song 5');
      final gesture = await t.startGesture(t.getCenter(cover));
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(const Offset(-260, 0));
      await t.pump();
      expect(nextCover, findsNothing);
      await gesture.up();
      await t.pumpAndSettle();
      expect(engine.loaded, ['hash5.mp3']);
    });

    testWidgets('with repeat all the last song swipes to the first', (t) async {
      final engine = await open(t, 'Song 5');
      await t.tap(find.byKey(const Key('player-repeat')));
      await t.pumpAndSettle();
      await t.drag(cover, const Offset(-200, 0));
      await t.pumpAndSettle();
      expect(engine.current, 'hash1.mp3');
    });

    testWidgets('shuffled under repeat all, the last song shows no next '
        'cover (the wrap shuffles again) but still swipes on', (t) async {
      final engine = await open(t, 'Song 1');
      await t.tap(find.byKey(const Key('player-shuffle')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('player-repeat')));
      await t.pumpAndSettle();
      final container = ProviderScope.containerOf(
        t.element(find.byType(OwntuneApp)),
      );
      final last = _state(t).queue.entries.last;
      await container.read(playerProvider.notifier).jumpTo(last.key);
      await t.pumpAndSettle();

      final gesture = await t.startGesture(t.getCenter(cover));
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(const Offset(-160, 0));
      await t.pump();
      expect(nextCover, findsNothing);
      await gesture.up();
      await t.pumpAndSettle();
      expect(engine.current, isNot('hash${last.trackId}.mp3'));
    });

    testWidgets('a song change during the slide skips nothing more', (t) async {
      final engine = await open(t, 'Song 2');
      final container = ProviderScope.containerOf(
        t.element(find.byType(OwntuneApp)),
      );
      await t.drag(cover, const Offset(-200, 0));
      // The slide is running; the song ends meanwhile.
      await t.pump(const Duration(milliseconds: 50));
      await container.read(playerProvider.notifier).next();
      await t.pumpAndSettle();
      expect(engine.current, 'hash3.mp3');
      expect(engine.loaded, ['hash2.mp3', 'hash3.mp3']);
    });

    testWidgets('swiping down on the cover still closes the player', (t) async {
      await open(t, 'Song 2');
      await t.drag(cover, const Offset(0, 600));
      await t.pumpAndSettle();
      expect(_sheet, findsNothing);
    });
  });
}

class _FailingLikeRepository extends FakeTrackRepository {
  @override
  Future<void> setLiked(Iterable<int> ids, {required bool liked}) async =>
      throw StateError('disk full');
}

const _tint = CoverColors(background: Color(0xff5a1e00));
const _tint2 = CoverColors(background: Color(0xff0a2a5a));

/// Settings with [mode]; the accent is Sky, to tell it from the tint.
Override _appearance(AppearanceMode mode) =>
    initialSettingsProvider.overrideWithValue(
      AppSettings(mode: mode, accent: const Color(0xff5ab4ff)),
    );

final _tinted = [
  track(
    1,
    title: 'After the Rain',
    cover: 'a.jpg',
    likedAt: DateTime(2026, 11, 20),
  ),
  track(2, title: 'Blue Hour', cover: 'b.jpg'),
  track(3, title: 'Coverless'),
];

Color? _playBackground(WidgetTester t) => t
    .widget<IconButton>(find.byKey(const Key('player-play')))
    .style
    ?.backgroundColor
    ?.resolve({});

Color? _iconColor(WidgetTester t, Key key) {
  final icon = find.descendant(
    of: find.byKey(key),
    matching: find.byType(Icon),
  );
  final widget = t.widget<Icon>(icon);
  return widget.color ?? IconTheme.of(t.element(icon)).color;
}

/// The flat background colour of the player sheet.
Color? _sheetColor(WidgetTester t) => t
    .widget<ColoredBox>(
      find.descendant(of: _sheet, matching: find.byType(ColoredBox)).first,
    )
    .color;

const _sky = Color(0xff5ab4ff);

void _tintTests() {
  group('cover tint', () {
    Future<void> openTinted(
      WidgetTester t,
      String title, {
      AppearanceMode mode = AppearanceMode.dark,
      Map<String, CoverColors> colors = const {'a.jpg': _tint, 'b.jpg': _tint2},
      bool never = false,
    }) async {
      await pumpApp(
        t,
        songs: _tinted,
        overrides: [
          _appearance(mode),
          coverColorsProvider.overrideWith(
            (ref, name) => never
                ? Completer<CoverColors?>().future
                : Future.value(colors[name]),
          ),
        ],
      );
      await openLibraryTab(t);
      await _open(t, title);
      await t.pump(const Duration(milliseconds: 500));
    }

    testWidgets('dark mode with a cover: flat cover colour, white controls', (
      t,
    ) async {
      await openTinted(t, 'After the Rain');
      expect(_sheetColor(t), _tint.background);
      expect(
        find.descendant(of: _sheet, matching: find.byType(ImageFiltered)),
        findsNothing,
        reason: 'no blurred cover, no gradient: a flat colour',
      );
      expect(_playBackground(t), tintAccent);
      expect(_iconColor(t, const Key('player-play')), tintOnAccent);
      expect(_iconColor(t, const Key('player-like')), tintAccent);
    });

    testWidgets('active repeat is white with a dot', (t) async {
      await openTinted(t, 'After the Rain');
      expect(find.byKey(const Key('player-repeat-dot')), findsNothing);
      await t.tap(find.byKey(const Key('player-repeat')));
      await t.pump(const Duration(milliseconds: 500));
      expect(_state(t).queue.repeat, QueueRepeat.all);
      final repeat = t.widget<IconButton>(
        find.byKey(const Key('player-repeat')),
      );
      expect(repeat.color, tintAccent);
      expect(find.byKey(const Key('player-repeat-dot')), findsOneWidget);
    });

    testWidgets('light mode keeps the accent', (t) async {
      await openTinted(t, 'After the Rain', mode: AppearanceMode.light);
      final c = Theme.of(t.element(find.byKey(const Key('player-play'))))
          .extension<OwntuneColors>()!;
      expect(_playBackground(t), c.accent);
      expect(_sheetColor(t), isNot(_tint.background));
    });

    testWidgets('a song without a cover keeps the accent', (t) async {
      await openTinted(t, 'Coverless');
      expect(_playBackground(t), _sky);
    });

    testWidgets('colours not ready keep the accent', (t) async {
      await openTinted(t, 'After the Rain', never: true);
      expect(_playBackground(t), _sky);
      expect(_sheetColor(t), isNot(_tint.background));
    });

    testWidgets('the tint follows a song change', (t) async {
      await openTinted(t, 'After the Rain');
      expect(_sheetColor(t), _tint.background);
      await t.tap(find.byKey(const Key('player-next')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(_sheetColor(t), _tint2.background);
      expect(_playBackground(t), tintAccent);
    });
  });

  testWidgets('the scrubber shows a dot at the current position', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: _songs, engine: engine);
    await openLibraryTab(t);
    await _open(t, 'After the Rain'); // 200 s long
    engine.emitPosition(const Duration(seconds: 50));
    await t.pumpAndSettle();
    final track = t.getRect(find.byKey(const Key('scrubber-track')));
    final dot = t.getRect(find.byKey(const Key('scrubber-thumb')));
    expect(
      dot.center.dx,
      moreOrLessEquals(track.left + track.width / 4, epsilon: 1),
    );
    expect(dot.center.dy, moreOrLessEquals(track.center.dy, epsilon: 1));
  });
}
