import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/playlist_repository.dart';

import '../support/fakes.dart';

final _songs = [
  track(1, title: 'Amber Lights', album: 'A', artist: 'x'),
  track(2, title: 'Backroads', album: 'B', artist: 'x'),
  track(3, title: 'Coastline', album: 'C', artist: 'x'),
];

/// Creates playlists but fails to add songs.
class _FailingAdd extends PlaylistRepository {
  _FailingAdd(super.db, super.storage, {required super.hash});

  @override
  Future<void> addTracks(int playlistId, List<int> trackIds) async =>
      throw StateError('disk full');
}

PlaylistRepository _repo() {
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  addTearDown(db.close);
  return PlaylistRepository(
    db,
    LibraryStorage(Directory('/nonexistent/owntune')),
    hash: (_) => 'h',
  );
}

/// Database calls run in real time, outside the test's fake clock.
Future<T> _real<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

/// Pumps the app with a playlist "Rainy Days" holding [trackIds].
Future<PlaylistRepository> _open(WidgetTester t, List<int> trackIds) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repo = _repo();
  await _real(t, () async {
    final id = await repo.create('Rainy Days');
    await repo.addTracks(id, trackIds);
  });
  await pumpApp(
    t,
    songs: _songs,
    playlists: repo,
    overrides: [
      trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
    ],
  );
  return repo;
}

Future<List<int>> _entries(WidgetTester t, PlaylistRepository repo) async {
  final entries = await _real(t, () => repo.watchEntries().first);
  entries.sort((a, b) => a.position.compareTo(b.position));
  return [for (final e in entries) e.trackId];
}

Future<void> _menuAddToPlaylist(WidgetTester t, String title) async {
  await t.longPress(find.text(title));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('menu-add-to-playlist')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('song menu Add to Playlist adds the song', (t) async {
    final repo = await _open(t, [2]);
    await _menuAddToPlaylist(t, 'Amber Lights');
    expect(find.text('Add to Playlist'), findsOneWidget);
    expect(find.text('“Amber Lights”'), findsOneWidget);
    expect(find.text('New Playlist…'), findsOneWidget);
    expect(find.text('1 song · 0 min'), findsOneWidget);

    await t.tap(find.text('Rainy Days'));
    await t.pumpAndSettle();
    expect(await _entries(t, repo), [2, 1]);
    expect(find.text('Add to Playlist'), findsNothing);
    expect(find.text('Added to Rainy Days'), findsOneWidget);
  });

  testWidgets(
    'a song already in the playlist asks before adding; Don\'t Add adds '
    'nothing; Add Anyway adds a second copy',
    (t) async {
      final repo = await _open(t, [1]);
      await _menuAddToPlaylist(t, 'Amber Lights');
      await t.tap(find.text('Rainy Days'));
      await t.pumpAndSettle();
      expect(find.text('Already added'), findsOneWidget);
      expect(
        find.text('“Amber Lights” is already in “Rainy Days”.'),
        findsOneWidget,
      );

      await t.tap(find.text('Don\'t Add'));
      await t.pumpAndSettle();
      expect(await _entries(t, repo), [1]);
      // Back at the sheet; picking again and confirming adds a copy.
      expect(find.text('Add to Playlist'), findsOneWidget);
      await t.tap(find.text('Rainy Days'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add Anyway'));
      await t.pumpAndSettle();
      expect(await _entries(t, repo), [1, 1]);
      expect(find.text('Add to Playlist'), findsNothing);
      expect(find.text('Added to Rainy Days'), findsOneWidget);
    },
  );

  Future<void> selectThree(WidgetTester t) async {
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Select'));
    await t.pumpAndSettle();
    for (final title in ['Amber Lights', 'Backroads', 'Coastline']) {
      await t.tap(find.text(title));
      await t.pump();
    }
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('selection-bar')),
        matching: find.text('Add to Playlist'),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('several songs: Add New Ones adds only the missing ones', (
    t,
  ) async {
    final repo = await _open(t, [2]);
    await selectThree(t);
    expect(find.text('3 songs'), findsOneWidget);
    await t.tap(find.text('Rainy Days'));
    await t.pumpAndSettle();
    expect(find.text('Already added'), findsOneWidget);
    expect(
      find.text('1 of these songs is already in “Rainy Days”.'),
      findsOneWidget,
    );
    await t.tap(find.text('Add New Ones'));
    await t.pumpAndSettle();
    expect(await _entries(t, repo), [2, 1, 3]);
  });

  testWidgets('several songs: Add All adds every selected song', (t) async {
    final repo = await _open(t, [2]);
    await selectThree(t);
    await t.tap(find.text('Rainy Days'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add All'));
    await t.pumpAndSettle();
    expect(await _entries(t, repo), [2, 1, 2, 3]);
  });

  testWidgets('all songs already in the playlist: only Cancel and Add All', (
    t,
  ) async {
    final repo = await _open(t, [1, 2, 3]);
    await selectThree(t);
    await t.tap(find.text('Rainy Days'));
    await t.pumpAndSettle();
    expect(
      find.text('3 of these songs are already in “Rainy Days”.'),
      findsOneWidget,
    );
    expect(find.text('Add New Ones'), findsNothing);
    expect(find.text('Add All'), findsOneWidget);
    await t.tap(find.text('Cancel').last);
    await t.pumpAndSettle();
    expect(await _entries(t, repo), [1, 2, 3]);
  });

  testWidgets('New Playlist… creates the playlist with the songs', (t) async {
    final repo = await _open(t, []);
    await _menuAddToPlaylist(t, 'Backroads');
    await t.tap(find.text('New Playlist…'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('new-playlist-name')), 'Focus');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('new-playlist-create')));
    await t.pumpAndSettle();

    final playlists = await _real(t, () => repo.watchPlaylists().first);
    expect([for (final p in playlists) p.name], ['Rainy Days', 'Focus']);
    expect(await _entries(t, repo), [2]);
    expect(find.text('Add to Playlist'), findsNothing);
    expect(find.text('Added to Focus'), findsOneWidget);
  });

  testWidgets('New Playlist… whose songs fail to add confirms nothing', (
    t,
  ) async {
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    final repo = _FailingAdd(
      db,
      LibraryStorage(Directory('/nonexistent/owntune')),
      hash: (_) => 'h',
    );
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pumpApp(
      t,
      songs: _songs,
      playlists: repo,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await _menuAddToPlaylist(t, 'Backroads');
    await t.tap(find.text('New Playlist…'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('new-playlist-name')), 'Focus');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('new-playlist-create')));
    await t.pumpAndSettle();

    expect(find.textContaining('disk full'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();

    expect(find.textContaining('Added to'), findsNothing);
    // The Add to Playlist sheet stays open, now listing the new playlist.
    expect(find.text('Add to Playlist'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);
  });

  testWidgets('Cancel closes the sheet without adding', (t) async {
    final repo = await _open(t, []);
    await _menuAddToPlaylist(t, 'Backroads');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Add to Playlist'), findsNothing);
    expect(await _entries(t, repo), isEmpty);
  });

  testWidgets('album page "…" adds the album in track order', (t) async {
    final repo = _repo();
    await _real(t, () => repo.create('Rainy Days'));
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pumpApp(
      t,
      songs: [
        track(1, title: 'Second', album: 'Lanterns', trackNumber: 2),
        track(2, title: 'Third', album: 'Lanterns', trackNumber: 3),
        track(3, title: 'First', album: 'Lanterns', trackNumber: 1),
      ],
      playlists: repo,
    );
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lanterns'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('detail-more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-add-to-playlist')));
    await t.pumpAndSettle();
    expect(find.text('3 songs'), findsOneWidget);
    await t.tap(find.text('Rainy Days'));
    await t.pumpAndSettle();
    expect(await _entries(t, repo), [3, 1, 2]);
  });

  testWidgets('artist page "…" adds the artist\'s songs', (t) async {
    final repo = _repo();
    await _real(t, () => repo.create('Rainy Days'));
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pumpApp(
      t,
      songs: [
        track(1, title: 'Bee', artist: 'Juno'),
        track(2, title: 'Ay', artist: 'Juno'),
        track(3, title: 'Other', artist: 'Mira'),
      ],
      playlists: repo,
    );
    await t.tap(find.text('Artists'));
    await t.pumpAndSettle();
    await t.tap(find.text('Juno'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('detail-more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-add-to-playlist')));
    await t.pumpAndSettle();
    await t.tap(find.text('Rainy Days'));
    await t.pumpAndSettle();
    expect(await _entries(t, repo), [2, 1]);
  });

  group('Liked Songs row', () {
    final songs = [
      track(1, title: 'Amber Lights', likedAt: DateTime(2026, 11, 20)),
      track(2, title: 'Backroads'),
      track(3, title: 'Coastline'),
    ];

    Future<void> openSheet(
      WidgetTester t,
      FakeTrackRepository repo, {
      List<String> select = const ['Amber Lights', 'Backroads', 'Coastline'],
    }) async {
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pumpApp(
        t,
        songs: songs,
        overrides: [trackRepositoryProvider.overrideWithValue(repo)],
      );
      await t.tap(find.byTooltip('More'));
      await t.pumpAndSettle();
      await t.tap(find.text('Select'));
      await t.pumpAndSettle();
      for (final title in select) {
        await t.tap(find.text(title));
        await t.pump();
      }
      await t.tap(
        find.descendant(
          of: find.byKey(const Key('selection-bar')),
          matching: find.text('Add to Playlist'),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('likes only the songs not liked yet and confirms', (t) async {
      final repo = FakeTrackRepository();
      await openSheet(t, repo);
      expect(find.byKey(const Key('add-to-playlist-liked')), findsOneWidget);
      expect(find.text('Liked Songs'), findsOneWidget);

      await t.tap(find.byKey(const Key('add-to-playlist-liked')));
      await t.pumpAndSettle();
      expect(repo.likeCalls.length, 1);
      expect(repo.likeCalls.single.ids, [2, 3]);
      expect(repo.likeCalls.single.liked, isTrue);
      expect(find.text('Already added'), findsNothing);
      expect(find.text('Added to Liked Songs'), findsOneWidget);
      expect(find.text('Add to Playlist'), findsNothing);
    });

    testWidgets('all already liked still confirms without a prompt', (t) async {
      final repo = FakeTrackRepository();
      await openSheet(t, repo, select: ['Amber Lights']);
      await t.tap(find.byKey(const Key('add-to-playlist-liked')));
      await t.pumpAndSettle();
      expect(repo.likeCalls, isEmpty);
      expect(find.text('Already added'), findsNothing);
      expect(find.text('Added to Liked Songs'), findsOneWidget);
    });

    testWidgets('a failed like shows the error and keeps the sheet open', (
      t,
    ) async {
      await openSheet(t, _FailingLike());
      await t.tap(find.byKey(const Key('add-to-playlist-liked')));
      await t.pumpAndSettle();
      expect(find.text("Couldn't add the songs"), findsOneWidget);
      expect(find.textContaining('disk full'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('Add to Playlist'), findsWidgets);
      expect(find.byKey(const Key('add-to-playlist-liked')), findsOneWidget);
      expect(find.text('Added to Liked Songs'), findsNothing);
    });
  });
}

/// Fails every like.
class _FailingLike extends FakeTrackRepository {
  @override
  Future<void> setLiked(Iterable<int> ids, {required bool liked}) async =>
      throw StateError('disk full');
}
