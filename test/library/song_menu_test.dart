import 'package:owntune/app/app_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/artist_screen.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/player/player_controller.dart';

import '../support/fakes.dart';

void main() {
  final songs = [
    track(
      1,
      title: 'Amber Lights',
      artist: 'Neon Harbor',
      album: 'Velvet Hours',
      trackNumber: 1,
    ),
    track(2, title: 'Loose Song'),
  ];

  Future<void> longPress(WidgetTester t, String title) async {
    await t.longPress(find.text(title));
    await t.pumpAndSettle();
  }

  Finder backLabel(String label) =>
      find.descendant(of: find.byType(NavRow), matching: find.text(label));

  testWidgets('Go to Album from Library › Songs shows back label Library', (
    t,
  ) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    await longPress(t, 'Amber Lights');
    expect(find.text('Go to Album'), findsOneWidget);
    expect(find.text('Go to Artist'), findsOneWidget);
    expect(find.text('Delete from Library'), findsOneWidget);

    await t.tap(find.text('Go to Album'));
    await t.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(backLabel('Library'), findsOneWidget);
  });

  testWidgets('the song menu has Add to Playlist right after Play Later', (
    t,
  ) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    await longPress(t, 'Amber Lights');
    final later = t.getTopLeft(find.byKey(const Key('menu-play-later'))).dy;
    final add = t.getTopLeft(find.byKey(const Key('menu-add-to-playlist'))).dy;
    expect(add, greaterThan(later));
    expect(add - later, lessThan(60));
    expect(find.text('Add to Playlist…'), findsOneWidget);
  });

  testWidgets('Go to Album is missing for a track without album', (t) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    await longPress(t, 'Loose Song');
    expect(find.text('Go to Album'), findsNothing);
    expect(find.text('Go to Artist'), findsOneWidget);
  });

  testWidgets('Go to Artist opens Unknown Artist for an untagged track', (
    t,
  ) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    await longPress(t, 'Loose Song');
    await t.tap(find.text('Go to Artist'));
    await t.pumpAndSettle();
    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(find.text('Unknown Artist'), findsOneWidget);
  });

  testWidgets('on the album screen the menu has no Go to Album', (t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    await t.tap(find.text('Velvet Hours'));
    await t.pumpAndSettle();
    await longPress(t, 'Amber Lights');
    expect(find.text('Go to Album'), findsNothing);
    expect(find.text('Go to Artist'), findsOneWidget);

    await t.tap(find.text('Go to Artist'));
    await t.pumpAndSettle();
    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(backLabel('Velvet Hours'), findsOneWidget);
  });

  testWidgets('on the artist screen the menu has no Go to Artist', (t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    await t.tap(find.text('Artists'));
    await t.pumpAndSettle();
    await t.tap(find.text('Neon Harbor'));
    await t.pumpAndSettle();
    await longPress(t, 'Amber Lights');
    expect(find.text('Go to Artist'), findsNothing);
    expect(find.text('Go to Album'), findsOneWidget);
  });

  group('Play Next and Play Later', () {
    final abc = [
      track(1, title: 'A song'),
      track(2, title: 'B song'),
      track(3, title: 'C song'),
    ];

    final repo = [
      trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
    ];

    List<int> queueIds(WidgetTester t) => [
      for (final e in ProviderScope.containerOf(
        t.element(find.byType(OwntuneApp)),
      ).read(playerProvider).queue.entries)
        e.trackId,
    ];

    testWidgets('Play Next inserts after the current song', (t) async {
      await pumpApp(t, songs: abc, overrides: repo);
      await openLibraryTab(t);
      await t.tap(find.text('A song'));
      await t.pumpAndSettle();

      await longPress(t, 'C song');
      await t.tap(find.byKey(const Key('menu-play-next')));
      await t.pumpAndSettle();

      expect(queueIds(t), [1, 3, 2, 3]);
    });

    testWidgets('Play Later appends to the queue', (t) async {
      await pumpApp(t, songs: abc, overrides: repo);
      await openLibraryTab(t);
      await t.tap(find.text('B song'));
      await t.pumpAndSettle();

      await longPress(t, 'A song');
      await t.tap(find.byKey(const Key('menu-play-later')));
      await t.pumpAndSettle();

      expect(queueIds(t), [1, 2, 3, 1]);
    });

    testWidgets('Play Next with nothing playing starts the song', (t) async {
      final engine = FakeAudioEngine();
      await pumpApp(t, songs: abc, engine: engine, overrides: repo);
      await openLibraryTab(t);

      await longPress(t, 'B song');
      await t.tap(find.byKey(const Key('menu-play-next')));
      await t.pumpAndSettle();

      expect(engine.current, 'hash2.mp3');
      expect(engine.playing, isTrue);
    });

    testWidgets('menu shows Play Next and Play Later above Go to Album', (
      t,
    ) async {
      await pumpApp(t, songs: songs, overrides: repo);
      await openLibraryTab(t);
      await longPress(t, 'Amber Lights');

      double y(String text) => t.getTopLeft(find.text(text)).dy;
      expect(y('Play Next'), lessThan(y('Play Later')));
      expect(y('Play Later'), lessThan(y('Go to Album')));
      expect(y('Go to Artist'), lessThan(y('Delete from Library')));
    });
  });

  testWidgets('Edit Info in the song menu opens the editor', (t) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    await longPress(t, 'Amber Lights');
    await t.tap(find.byKey(const Key('menu-edit')));
    await t.pumpAndSettle();
    expect(find.text('Edit Info'), findsOneWidget);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('edit-field-title')))
          .controller!
          .text,
      'Amber Lights',
    );
  });

  testWidgets('tapping the "…" on a Songs row opens the song menu', (t) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    expect(find.byKey(const Key('song-more-1')), findsOneWidget);
    final semantics = t.ensureSemantics();
    await t.pump();
    expect(find.bySemanticsLabel('More'), findsWidgets);
    semantics.dispose();
    await t.tap(find.byKey(const Key('song-more-1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu-play-next')), findsOneWidget);
    expect(find.text('Go to Album'), findsOneWidget);
    // The menu opens at the button, not at the row's left edge.
    final button = t.getBottomRight(find.byKey(const Key('song-more-1')));
    final menu = t.getTopLeft(find.byKey(const Key('menu-play-next')));
    expect((menu.dx - button.dx).abs(), lessThan(300));
    expect(menu.dx, greaterThan(300));
  });

  testWidgets('the "…" does not start playback', (t) async {
    final engine = FakeAudioEngine();
    await pumpApp(
      t,
      songs: songs,
      engine: engine,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    await t.tap(find.byKey(const Key('song-more-1')));
    await t.pumpAndSettle();
    expect(engine.loaded, isEmpty);
  });

  testWidgets('long-press on a row still opens the menu', (t) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await openLibraryTab(t);
    await longPress(t, 'Amber Lights');
    expect(find.byKey(const Key('menu-play-next')), findsOneWidget);
  });

  testWidgets('menu offers Add to Liked Songs for an unliked song', (t) async {
    final repo = FakeTrackRepository();
    await pumpApp(
      t,
      songs: songs,
      overrides: [trackRepositoryProvider.overrideWithValue(repo)],
    );
    await openLibraryTab(t);
    await longPress(t, 'Amber Lights');
    expect(find.text('Remove from Liked Songs'), findsNothing);
    final add = t.getTopLeft(find.byKey(const Key('menu-add-to-playlist'))).dy;
    final like = t.getTopLeft(find.byKey(const Key('menu-like'))).dy;
    expect(like, greaterThan(add));
    expect(like - add, lessThan(60));

    await t.tap(find.text('Add to Liked Songs'));
    await t.pumpAndSettle();
    expect(repo.likeCalls.map((c) => (c.ids.single, c.liked)), [(1, true)]);
  });

  testWidgets('menu offers Remove from Liked Songs for a liked song', (
    t,
  ) async {
    final repo = FakeTrackRepository();
    await pumpApp(
      t,
      songs: [track(1, title: 'Amber Lights', likedAt: DateTime(2026, 11, 24))],
      overrides: [trackRepositoryProvider.overrideWithValue(repo)],
    );
    await openLibraryTab(t);
    await longPress(t, 'Amber Lights');
    expect(find.text('Add to Liked Songs'), findsNothing);

    await t.tap(find.text('Remove from Liked Songs'));
    await t.pumpAndSettle();
    expect(repo.likeCalls.map((c) => (c.ids.single, c.liked)), [(1, false)]);
  });

  testWidgets('a failed like shows a dialog', (t) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(_FailingLikeRepository()),
      ],
    );
    await openLibraryTab(t);
    await longPress(t, 'Amber Lights');
    await t.tap(find.text('Add to Liked Songs'));
    await t.pumpAndSettle();

    expect(find.text('Could not update Liked Songs'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Could not update Liked Songs'), findsNothing);
  });
}

class _FailingLikeRepository extends FakeTrackRepository {
  @override
  Future<void> setLiked(Iterable<int> ids, {required bool liked}) async =>
      throw StateError('disk full');
}
