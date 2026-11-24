import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/playlist_repository.dart';
import 'package:owntune/playlists/new_playlist_sheet.dart';

import '../support/fakes.dart';

Uint8List _png() {
  final image = img.Image(width: 60, height: 40);
  img.fill(image, color: img.ColorRgb8(0, 128, 255));
  return img.encodePng(image);
}

void main() {
  late PlaylistRepository repo;
  late LibraryStorage storage;
  int? result;

  Future<void> open(
    WidgetTester t, {
    List<int> addTrackIds = const [],
    FakeCoverPicker? picker,
    bool failing = false,
  }) async {
    final tmp = Directory.systemTemp.createTempSync('owntune_new_playlist');
    addTearDown(() => tmp.deleteSync(recursive: true));
    storage = LibraryStorage(tmp);
    await t.runAsync(storage.ensure);
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    repo = failing
        ? _FailingRepo(db, storage)
        : PlaylistRepository(db, storage, hash: (_) => 'newcover');
    result = null;
    await pumpApp(
      t,
      songs: [track(1), track(2)],
      playlists: repo,
      storage: storage,
      coverPicker: picker,
    );
    final context = t.element(find.byType(Scaffold).first);
    // ignore: unawaited_futures
    showNewPlaylistSheet(
      context,
      addTrackIds: addTrackIds,
    ).then((id) => result = id);
    await t.pumpAndSettle();
  }

  /// Isolates and file writes need real time: waits until [done] is true.
  Future<void> settleUntil(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  Future<void> pickCover(WidgetTester t) async {
    await t.tap(find.text('Add Cover'));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose from Photos'));
    await settleUntil(t, () => find.text('Choose').evaluate().isNotEmpty);
    await t.tap(find.text('Choose'));
    await settleUntil(
      t,
      () => find
          .byKey(const Key('new-playlist-cover-preview'))
          .evaluate()
          .isNotEmpty,
    );
  }

  testWidgets('Create adds the given songs and returns the new id', (t) async {
    await open(t, addTrackIds: [2, 1, 2]);
    await t.enterText(find.byKey(const Key('new-playlist-name')), ' Mix ');
    await t.pump();
    await t.tap(find.byKey(const Key('new-playlist-create')));
    await t.pumpAndSettle();

    final entries = (await t.runAsync(() => repo.watchEntries().first))!;
    expect(entries.map((e) => e.trackId), [2, 1, 2]);
    final playlists = (await t.runAsync(() => repo.watchPlaylists().first))!;
    expect(playlists.single.name, 'Mix');
    expect(result, playlists.single.id);
  });

  testWidgets('Cancel returns null', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('new-playlist-cancel')));
    await t.pumpAndSettle();
    expect(result, isNull);
    expect(find.byKey(const Key('new-playlist-name')), findsNothing);
  });

  testWidgets('a picked cover is previewed and Remove Cover clears it', (
    t,
  ) async {
    await open(t, picker: FakeCoverPicker(photo: _png()));
    // No cover yet: no Remove Cover.
    await t.tap(find.text('Add Cover'));
    await t.pumpAndSettle();
    expect(find.text('Playlist Cover'), findsOneWidget);
    expect(find.text('Remove Cover'), findsNothing);
    await t.tap(find.text('Cancel').last);
    await t.pumpAndSettle();

    await pickCover(t);
    expect(find.byKey(const Key('new-playlist-cover-preview')), findsOneWidget);

    await t.tap(find.text('Add Cover'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove Cover'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('new-playlist-cover-preview')), findsNothing);
  });

  testWidgets('Create stores the picked cover', (t) async {
    await open(t, picker: FakeCoverPicker(photo: _png()));
    await pickCover(t);
    await t.enterText(find.byKey(const Key('new-playlist-name')), 'Mix');
    await t.pump();
    await t.tap(find.byKey(const Key('new-playlist-create')));
    await settleUntil(t, () => result != null);

    final playlist = (await t.runAsync(() => repo.watchPlaylists().first))!
        .single;
    expect(playlist.coverFile, 'newcover.jpg');
    expect(storage.coverFile('newcover.jpg').existsSync(), isTrue);
  });

  testWidgets('a failing create shows the error and keeps the sheet', (
    t,
  ) async {
    await open(t, failing: true);
    await t.enterText(find.byKey(const Key('new-playlist-name')), 'Mix');
    await t.pump();
    await t.tap(find.byKey(const Key('new-playlist-create')));
    await t.pumpAndSettle();
    expect(find.text("Couldn't create the playlist"), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('new-playlist-name')), findsOneWidget);
    expect(result, isNull);
  });
}

class _FailingRepo extends PlaylistRepository {
  _FailingRepo(super.db, super.storage) : super(hash: _noHash);

  static String _noHash(Uint8List _) => 'x';

  @override
  Future<int> create(String name, {Uint8List? cover}) =>
      Future.error(StateError('disk full'));
}
