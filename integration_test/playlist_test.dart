import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/playlist_repository.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/src/rust/api/library.dart';
import 'package:owntune/src/rust/api/metadata.dart';
import 'package:owntune/src/rust/frb_generated.dart';

import 'support/fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('playlists survive a restart and clean up their cover', (
    t,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('owntune_playlist_it');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final picked = [
      for (final name in ['tagged.mp3', 'tagged.m4a'])
        File('${fixturesDir().path}/$name').copySync('${tmp.path}/$name').path,
    ];
    final storage = LibraryStorage(Directory('${tmp.path}/library'));
    await storage.ensure();
    final dbFile = File('${tmp.path}/owntune.sqlite');

    var db = AppDatabase(NativeDatabase(dbFile));
    var closed = false;
    addTearDown(() async {
      if (!closed) await db.close();
    });
    var tracks = TrackRepository(db, storage);
    await Importer(
      repo: tracks,
      storage: storage,
      read: (p) => readTrack(path: p),
      supportedExtensions: supportedFormats().toSet(),
    ).importFiles(picked);
    final imported = await tracks.watchAll().first;
    expect(imported, hasLength(2));

    final image = img.Image(width: 64, height: 64);
    img.fill(image, color: img.ColorRgb8(200, 40, 90));
    final Uint8List jpeg = img.encodeJpg(image);
    final coverName = '${hashBytes(data: jpeg)}.jpg';

    var playlists = PlaylistRepository(
      db,
      storage,
      hash: (data) => hashBytes(data: data),
    );
    final id = await playlists.create('Road Trip', cover: jpeg);
    await playlists.addTracks(id, [for (final t in imported) t.id]);
    expect(storage.coverFile(coverName).existsSync(), isTrue);
    var entries = await playlists.watchEntries().first;
    expect(entries.map((e) => e.position), [0, 1]);

    // Deleting a song from the library removes its entry and renumbers.
    await tracks.delete(imported.first.id);
    entries = await playlists.watchEntries().first;
    expect(entries.map((e) => e.trackId), [imported.last.id]);
    expect(entries.single.position, 0);

    // Restart: close the database and open the same file again.
    await db.close();
    closed = true;
    db = AppDatabase(NativeDatabase(dbFile));
    closed = false;
    tracks = TrackRepository(db, storage);
    playlists = PlaylistRepository(
      db,
      storage,
      hash: (data) => hashBytes(data: data),
    );
    final reopened = await playlists.watchPlaylists().first;
    expect(reopened.single.name, 'Road Trip');
    expect(reopened.single.coverFile, coverName);
    expect(storage.coverFile(coverName).existsSync(), isTrue);
    expect((await playlists.watchEntries().first), hasLength(1));

    // Startup cleanup keeps the playlist's cover.
    await tracks.cleanupOrphans();
    expect(storage.coverFile(coverName).existsSync(), isTrue);

    await playlists.delete(id);
    expect(await playlists.watchPlaylists().first, isEmpty);
    expect(await playlists.watchEntries().first, isEmpty);
    expect(storage.coverFile(coverName).existsSync(), isFalse);
  });
}
