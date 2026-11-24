import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/playlist_repository.dart';
import 'package:owntune/playlists/edit_playlist_screen.dart';

import '../support/fakes.dart';

final _songs = [
  track(1, title: 'Amber Lights', album: 'A', artist: 'x', durationMs: 240000),
  track(2, title: 'Backroads', album: 'B', artist: 'x', durationMs: 240000),
  track(3, title: 'Coastline', album: 'C', artist: 'x', durationMs: 240000),
];

/// Database calls run in real time, outside the test's fake clock.
Future<T> _real<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

class _Setup {
  _Setup(this.repo, this.songs);

  final PlaylistRepository repo;
  final StreamController<List<Track>> songs;

  Future<List<int>> trackIds(WidgetTester t) async {
    final entries = await _real(t, () => repo.watchEntries().first);
    entries.sort((a, b) => a.position.compareTo(b.position));
    return [for (final e in entries) e.trackId];
  }

  Future<Playlist> playlist(WidgetTester t) async =>
      (await _real(t, () => repo.watchPlaylists().first)).single;
}

/// Pumps the app with one playlist "Rainy Days" holding [trackIds] and opens
/// its editor through the page's "…" menu.
Future<_Setup> _open(
  WidgetTester t,
  List<int> trackIds, {
  Uint8List? cover,
  FakeCoverPicker? picker,
}) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  addTearDown(db.close);
  final tmp = Directory.systemTemp.createTempSync('owntune_edit_playlist');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final storage = LibraryStorage(tmp);
  await t.runAsync(storage.ensure);
  final repo = PlaylistRepository(db, storage, hash: (_) => 'h');
  await _real(t, () async {
    final id = await repo.create('Rainy Days', cover: cover);
    await repo.addTracks(id, trackIds);
  });
  final songs = StreamController<List<Track>>();
  addTearDown(songs.close);
  songs.add(_songs);
  await pumpApp(
    t,
    songsStream: songs.stream,
    playlists: repo,
    storage: storage,
    coverPicker: picker,
    overrides: [
      trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
    ],
  );
  await t.tap(find.text('Playlists').last);
  await t.pumpAndSettle();
  await t.tap(find.text('Rainy Days'));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('detail-more')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('menu-edit-playlist')));
  await t.pumpAndSettle();
  return _Setup(repo, songs);
}

/// Picking decodes and crops in isolates, which need real time.
Future<void> _settleIsolates(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump();
  }
  await t.pumpAndSettle();
}

Finder get _done => find.byKey(const Key('edit-playlist-done'));

TextButton _doneButton(WidgetTester t) => t.widget<TextButton>(_done);

void main() {
  testWidgets('opens as a full-screen page with the draft', (t) async {
    await _open(t, [2, 1]);
    expect(find.byType(EditPlaylistScreen), findsOneWidget);
    expect(find.text('Edit Playlist'), findsOneWidget);
    expect(find.text('Edit Cover'), findsOneWidget);
    expect(find.text('2 songs · drag to reorder'), findsOneWidget);
    final field = t.widget<TextField>(
      find.byKey(const Key('edit-playlist-name')),
    );
    expect(field.controller!.text, 'Rainy Days');
    expect(
      t.getTopLeft(find.text('Backroads')).dy,
      lessThan(t.getTopLeft(find.text('Amber Lights')).dy),
    );
  });

  testWidgets('Cancel changes nothing', (t) async {
    final s = await _open(t, [1, 2]);
    await t.enterText(find.byKey(const Key('edit-playlist-name')), 'Other');
    await t.tap(find.byKey(const Key('edit-playlist-remove-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('edit-playlist-cancel')));
    await t.pumpAndSettle();
    expect(find.byType(EditPlaylistScreen), findsNothing);
    expect((await s.playlist(t)).name, 'Rainy Days');
    expect(await s.trackIds(t), [1, 2]);
  });

  testWidgets('rename and Done saves the trimmed name', (t) async {
    final s = await _open(t, [1, 2]);
    await t.enterText(
      find.byKey(const Key('edit-playlist-name')),
      '  Sunny Days  ',
    );
    await t.pump();
    await t.tap(_done);
    await t.pumpAndSettle();
    expect(find.byType(EditPlaylistScreen), findsNothing);
    expect((await s.playlist(t)).name, 'Sunny Days');
    expect(await s.trackIds(t), [1, 2]);
    expect(find.text('Sunny Days'), findsOneWidget);
  });

  testWidgets('Done is disabled for a blank name', (t) async {
    await _open(t, [1]);
    expect(_doneButton(t).onPressed, isNotNull);
    await t.enterText(find.byKey(const Key('edit-playlist-name')), '   ');
    await t.pump();
    expect(_doneButton(t).onPressed, isNull);
    await t.enterText(find.byKey(const Key('edit-playlist-name')), '');
    await t.pump();
    expect(_doneButton(t).onPressed, isNull);
    await t.enterText(find.byKey(const Key('edit-playlist-name')), 'x');
    await t.pump();
    expect(_doneButton(t).onPressed, isNotNull);
  });

  testWidgets('removing a row and Done deletes only that entry', (t) async {
    final s = await _open(t, [1, 2, 1]);
    // Entries 1 and 3 are the same song; remove only the second copy.
    await t.tap(find.byKey(const Key('edit-playlist-remove-3')));
    await t.pumpAndSettle();
    expect(find.text('2 songs · drag to reorder'), findsOneWidget);
    await t.tap(_done);
    await t.pumpAndSettle();
    expect(await s.trackIds(t), [1, 2]);
    expect(find.text('2 songs · 8 min'), findsOneWidget);
  });

  testWidgets('dragging reorders', (t) async {
    final s = await _open(t, [1, 2, 3]);
    // Move in small steps, like a finger does.
    final g = await t.startGesture(
      t.getCenter(find.byKey(const Key('edit-playlist-handle-1'))),
    );
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, 10));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
    await t.tap(_done);
    await t.pumpAndSettle();
    expect(await s.trackIds(t), [2, 1, 3]);
  });

  testWidgets('a song deleted while editing is dropped and Done succeeds', (
    t,
  ) async {
    final s = await _open(t, [1, 2, 3]);
    s.songs.add([_songs[0], _songs[2]]);
    await t.pumpAndSettle();
    expect(find.text('Backroads'), findsNothing);
    expect(find.text('2 songs · drag to reorder'), findsOneWidget);
    await t.tap(_done);
    await t.pumpAndSettle();
    expect(find.byType(EditPlaylistScreen), findsNothing);
    expect(t.takeException(), isNull);
    expect(await s.trackIds(t), [1, 3]);
  });

  group('cover', () {
    testWidgets('Remove Cover clears the custom cover', (t) async {
      final s = await _open(t, [1], cover: Uint8List.fromList([1, 2, 3]));
      expect((await s.playlist(t)).coverFile, 'h.jpg');
      await t.tap(find.text('Edit Cover'));
      await t.pumpAndSettle();
      expect(find.text('Playlist Cover'), findsOneWidget);
      await t.tap(find.text('Remove Cover'));
      await t.pumpAndSettle();
      await t.tap(_done);
      await t.pumpAndSettle();
      expect((await s.playlist(t)).coverFile, isNull);
    });

    testWidgets('a picked cover is stored with Done', (t) async {
      final image = img.Image(width: 60, height: 40);
      img.fill(image, color: img.ColorRgb8(0, 128, 255));
      final s = await _open(t, [
        1,
      ], picker: FakeCoverPicker(photo: img.encodePng(image)));
      await t.tap(find.text('Edit Cover'));
      await t.pumpAndSettle();
      await t.tap(find.text('Choose from Photos'));
      await _settleIsolates(t);
      expect(find.text('Move and Scale'), findsOneWidget);
      await t.tap(find.text('Choose'));
      await _settleIsolates(t);
      expect(
        find.descendant(
          of: find.byKey(const Key('edit-playlist-cover')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      expect((await s.playlist(t)).coverFile, isNull);
      await t.tap(_done);
      await _settleIsolates(t); // storing the cover writes a file
      expect((await s.playlist(t)).coverFile, 'h.jpg');
    });

    testWidgets('Remove Cover is hidden without a custom cover', (t) async {
      await _open(t, [1]);
      await t.tap(find.text('Edit Cover'));
      await t.pumpAndSettle();
      expect(find.text('Playlist Cover'), findsOneWidget);
      expect(find.text('Choose from Photos'), findsOneWidget);
      expect(find.text('Choose File'), findsOneWidget);
      expect(find.text('Remove Cover'), findsNothing);
    });
  });
}
