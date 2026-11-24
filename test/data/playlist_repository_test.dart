import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/playlist_repository.dart';
import 'package:owntune/data/track_repository.dart';

String _hash(Uint8List b) => 'h${b.length}';

void main() {
  late Directory tmp;
  late LibraryStorage storage;
  late AppDatabase db;
  late PlaylistRepository repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('owntune_playlist_test');
    storage = LibraryStorage(Directory('${tmp.path}/library'));
    await storage.ensure();
    db = AppDatabase(NativeDatabase.memory());
    repo = PlaylistRepository(db, storage, hash: _hash);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Uint8List jpeg(int length) => Uint8List.fromList(List.filled(length, 7));

  Future<List<PlaylistEntry>> entries(int playlistId) async {
    final all = await (db.select(
      db.playlistEntries,
    )..where((e) => e.playlistId.equals(playlistId))).get();
    all.sort((a, b) => a.position.compareTo(b.position));
    return all;
  }

  Future<Playlist> playlist(int id) =>
      (db.select(db.playlists)..where((p) => p.id.equals(id))).getSingle();

  test('create trims the name and starts empty', () async {
    final id = await repo.create('  Rainy Days ');

    final p = await playlist(id);
    expect(p.name, 'Rainy Days');
    expect(p.coverFile, isNull);
    expect(await entries(id), isEmpty);
    expect((await repo.watchPlaylists().first).single.id, id);
  });

  test('create with a cover stores it', () async {
    final id = await repo.create('A', cover: jpeg(4));

    expect((await playlist(id)).coverFile, 'h4.jpg');
    expect(storage.coverFile('h4.jpg').existsSync(), isTrue);
  });

  test('addTracks appends in order and keeps duplicates', () async {
    final id = await repo.create('A');

    await repo.addTracks(id, [1, 2]);
    await repo.addTracks(id, [1]);

    final e = await entries(id);
    expect([for (final x in e) x.trackId], [1, 2, 1]);
    expect([for (final x in e) x.position], [0, 1, 2]);
    expect(await repo.watchEntries().first, hasLength(3));
  });

  test('removeEntry removes one copy and renumbers', () async {
    final id = await repo.create('A');
    await repo.addTracks(id, [1, 2, 1]);
    final before = await entries(id);

    await repo.removeEntry(before.last.id);

    final e = await entries(id);
    expect([for (final x in e) x.trackId], [1, 2]);
    expect([for (final x in e) x.position], [0, 1]);
    expect(e.first.id, before.first.id);
  });

  test('removeEntry renumbers a gap in the middle', () async {
    final id = await repo.create('A');
    await repo.addTracks(id, [1, 2, 3]);
    final before = await entries(id);

    await repo.removeEntry(before[1].id);

    final e = await entries(id);
    expect([for (final x in e) x.trackId], [1, 3]);
    expect([for (final x in e) x.position], [0, 1]);
  });

  test('saveEdit reorders, drops missing entries, renames', () async {
    final id = await repo.create('A');
    await repo.addTracks(id, [1, 2, 3]);
    final before = await entries(id);
    final (a, b, c) = (before[0], before[1], before[2]);

    await repo.saveEdit(
      id,
      name: '  New  ',
      entryIds: [c.id, a.id, 999],
      cover: const PlaylistCoverKeep(),
    );

    final e = await entries(id);
    expect([for (final x in e) x.id], [c.id, a.id]);
    expect([for (final x in e) x.position], [0, 1]);
    expect(e.any((x) => x.id == b.id), isFalse);
    expect((await playlist(id)).name, 'New');
  });

  test('saveEdit keeps positions dense when a listed entry is gone', () async {
    final id = await repo.create('A');
    final other = await repo.create('B');
    await repo.addTracks(id, [1, 2, 3]);
    await repo.addTracks(other, [4]);
    final before = await entries(id);
    final foreign = (await entries(other)).single;
    await repo.removeEntry(before[1].id);

    await repo.saveEdit(
      id,
      name: 'A',
      entryIds: [before[2].id, before[1].id, foreign.id, before[0].id],
      cover: const PlaylistCoverKeep(),
    );

    final e = await entries(id);
    expect([for (final x in e) x.id], [before[2].id, before[0].id]);
    expect([for (final x in e) x.position], [0, 1]);
  });

  test('saveEdit does not touch other playlists', () async {
    final id = await repo.create('A');
    final other = await repo.create('B');
    await repo.addTracks(id, [1]);
    await repo.addTracks(other, [2]);
    final otherEntry = (await entries(other)).single;

    await repo.saveEdit(
      id,
      name: 'A',
      entryIds: [otherEntry.id],
      cover: const PlaylistCoverKeep(),
    );

    expect(await entries(id), isEmpty);
    expect((await entries(other)).single.id, otherEntry.id);
  });

  test('saveEdit with a new cover stores it and deletes the unused old '
      'one', () async {
    final id = await repo.create('A', cover: jpeg(4));

    await repo.saveEdit(
      id,
      name: 'A',
      entryIds: const [],
      cover: PlaylistCoverSet(jpeg(6)),
    );

    expect((await playlist(id)).coverFile, 'h6.jpg');
    expect(storage.coverFile('h6.jpg').existsSync(), isTrue);
    expect(storage.coverFile('h4.jpg').existsSync(), isFalse);
  });

  test('saveEdit keeps the old cover file when a track still uses '
      'it', () async {
    final id = await repo.create('A', cover: jpeg(4));
    await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            fileName: 't.mp3',
            originalName: 't.mp3',
            contentHash: 't',
            durationMs: 1000,
            addedAt: DateTime(2026, 1, 1),
            coverFile: const Value('h4.jpg'),
          ),
        );

    await repo.saveEdit(
      id,
      name: 'A',
      entryIds: const [],
      cover: const PlaylistCoverRemove(),
    );

    expect((await playlist(id)).coverFile, isNull);
    expect(storage.coverFile('h4.jpg').existsSync(), isTrue);
  });

  test('saveEdit with the same cover image keeps the file', () async {
    final id = await repo.create('A', cover: jpeg(4));

    await repo.saveEdit(
      id,
      name: 'A',
      entryIds: const [],
      cover: PlaylistCoverSet(jpeg(4)),
    );

    expect((await playlist(id)).coverFile, 'h4.jpg');
    expect(storage.coverFile('h4.jpg').existsSync(), isTrue);
  });

  test('saveEdit keep leaves the cover alone', () async {
    final id = await repo.create('A', cover: jpeg(4));

    await repo.saveEdit(
      id,
      name: 'B',
      entryIds: const [],
      cover: const PlaylistCoverKeep(),
    );

    expect((await playlist(id)).coverFile, 'h4.jpg');
    expect(storage.coverFile('h4.jpg').existsSync(), isTrue);
  });

  test('delete removes entries, row and unused cover', () async {
    final id = await repo.create('A', cover: jpeg(4));
    final other = await repo.create('B');
    await repo.addTracks(id, [1, 2]);
    await repo.addTracks(other, [1]);

    await repo.delete(id);

    expect(await db.select(db.playlists).get(), hasLength(1));
    expect(await db.select(db.playlistEntries).get(), hasLength(1));
    expect(storage.coverFile('h4.jpg').existsSync(), isFalse);
  });

  test('delete keeps a cover that a track uses', () async {
    final id = await repo.create('A', cover: jpeg(4));
    await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            fileName: 't.mp3',
            originalName: 't.mp3',
            contentHash: 't',
            durationMs: 1000,
            addedAt: DateTime(2026, 1, 1),
            coverFile: const Value('h4.jpg'),
          ),
        );

    await repo.delete(id);

    expect(storage.coverFile('h4.jpg').existsSync(), isTrue);
    expect(await isCoverInUse(db, 'h4.jpg'), isTrue);
  });
}
