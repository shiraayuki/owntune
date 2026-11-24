import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/edit/track_tags.dart';

TracksCompanion row(
  String hash, {
  String ext = 'mp3',
  String? cover,
  String title = 'Song',
}) {
  return TracksCompanion.insert(
    fileName: '$hash.$ext',
    originalName: '$title.$ext',
    contentHash: hash,
    durationMs: 1000,
    addedAt: DateTime(2026, 1, 1),
    title: Value(title),
    coverFile: Value(cover),
  );
}

void main() {
  late Directory tmp;
  late LibraryStorage storage;
  late AppDatabase db;
  late TrackRepository repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('owntune_repo_test');
    storage = LibraryStorage(Directory('${tmp.path}/library'));
    await storage.ensure();
    db = AppDatabase(NativeDatabase.memory());
    repo = TrackRepository(db, storage);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  void writeAudio(String name, [int bytes = 10]) =>
      storage.audioFile(name).writeAsBytesSync(List.filled(bytes, 1));
  void writeCover(String name, [int bytes = 5]) =>
      storage.coverFile(name).writeAsBytesSync(List.filled(bytes, 2));

  test('insert then watchAll emits the track', () async {
    await repo.insert(row('h1'));

    final tracks = await repo.watchAll().first;

    expect(tracks, hasLength(1));
    expect(tracks.single.fileName, 'h1.mp3');
    expect(tracks.single.title, 'Song');
    expect(tracks.single.playCount, 0);
    expect(await repo.count(), 1);
  });

  test('hasHash is true only for inserted hashes', () async {
    await repo.insert(row('h1'));

    expect(await repo.hasHash('h1'), isTrue);
    expect(await repo.hasHash('other'), isFalse);
  });

  test('delete removes row, audio file and unshared cover', () async {
    writeAudio('h1.mp3');
    writeAudio('h2.mp3');
    writeCover('c1.jpg');
    await repo.insert(row('h1', cover: 'c1.jpg'));
    await repo.insert(row('h2', cover: 'c1.jpg'));
    final tracks = await repo.watchAll().first;
    final first = tracks.firstWhere((t) => t.fileName == 'h1.mp3');
    final second = tracks.firstWhere((t) => t.fileName == 'h2.mp3');

    await repo.delete(first.id);

    expect(await repo.count(), 1);
    expect(storage.audioFile('h1.mp3').existsSync(), isFalse);
    expect(storage.audioFile('h2.mp3').existsSync(), isTrue);
    expect(storage.coverFile('c1.jpg').existsSync(), isTrue);

    await repo.delete(second.id);

    expect(await repo.count(), 0);
    expect(storage.audioFile('h2.mp3').existsSync(), isFalse);
    expect(storage.coverFile('c1.jpg').existsSync(), isFalse);
  });

  test('delete of a missing id and missing files does not throw', () async {
    await repo.insert(row('h1', cover: 'c1.jpg'));
    final id = (await repo.watchAll().first).single.id;

    await repo.delete(id);
    await repo.delete(id);

    expect(await repo.count(), 0);
  });

  test(
    'cleanupOrphans skips files it cannot delete and removes the rest',
    () async {
      writeAudio('stuck.part.mp3');
      writeAudio('orphan.mp3');
      writeCover('orphan.png');
      writeCover('abc.part');
      // A read-only directory makes every delete inside it fail.
      await Process.run('chmod', ['0555', storage.audioDir.path]);
      addTearDown(() => Process.run('chmod', ['0755', storage.audioDir.path]));

      await repo.cleanupOrphans();

      expect(storage.audioFile('stuck.part.mp3').existsSync(), isTrue);
      expect(storage.audioFile('orphan.mp3').existsSync(), isTrue);
      expect(storage.coverFile('orphan.png').existsSync(), isFalse);
      expect(storage.coverFile('abc.part').existsSync(), isFalse);
    },
  );

  test('cleanupOrphans skips a directory it cannot list', () async {
    writeAudio('orphan.mp3');
    writeCover('orphan.png');
    await Process.run('chmod', ['0000', storage.audioDir.path]);
    addTearDown(() => Process.run('chmod', ['0755', storage.audioDir.path]));

    await repo.cleanupOrphans();

    expect(storage.coverFile('orphan.png').existsSync(), isFalse);
  });

  test('cleanupOrphans removes part files and files without rows, '
      'keeps referenced files', () async {
    writeAudio('h1.mp3');
    writeCover('c1.jpg');
    await repo.insert(row('h1', cover: 'c1.jpg'));
    writeAudio('h1.mp3.part');
    writeAudio('stray.flac');
    writeCover('stray.jpg');

    await repo.cleanupOrphans();

    expect(storage.audioFile('h1.mp3').existsSync(), isTrue);
    expect(storage.coverFile('c1.jpg').existsSync(), isTrue);
    expect(storage.audioFile('h1.mp3.part').existsSync(), isFalse);
    expect(storage.audioFile('stray.flac').existsSync(), isFalse);
    expect(storage.coverFile('stray.jpg').existsSync(), isFalse);
  });

  test('storageBytes sums audio and cover files', () async {
    writeAudio('a.mp3', 100);
    writeAudio('b.flac', 50);
    writeCover('c.jpg', 7);

    expect(await repo.storageBytes(), 157);
  });

  test('rows hold names only', () async {
    await repo.insert(row('h1', cover: 'c1.jpg'));

    final track = (await repo.watchAll().first).single;

    expect(track.fileName, isNot(contains('/')));
    expect(track.coverFile, isNot(contains('/')));
    expect(
      storage.audioFile(track.fileName).path,
      startsWith(storage.root.path),
    );
  });

  test('markPlayed increments the play count and sets lastPlayedAt', () async {
    await repo.insert(row('h1'));
    final id = (await repo.watchAll().first).single.id;
    final before = DateTime.now().subtract(const Duration(seconds: 1));

    await repo.markPlayed(id);
    await repo.markPlayed(id);

    final t = (await repo.watchAll().first).single;
    expect(t.playCount, 2);
    expect(t.lastPlayedAt!.isAfter(before), isTrue);
  });

  test('updateTags writes all columns and keeps hash and file name', () async {
    await repo.insert(row('h1'));
    await repo.insert(row('h2', title: 'Other'));
    final ids = [for (final t in await repo.watchAll().first) t.id];

    await repo.updateTags({
      ids.first: const TrackTags(
        title: 'New',
        artist: 'Artist',
        album: 'Album',
        albumArtist: 'Album Artist',
        genre: 'Genre',
        trackNumber: 3,
        discNumber: 1,
        year: 2020,
      ),
    });

    final tracks = await repo.watchAll().first;
    final t = tracks.firstWhere((t) => t.id == ids.first);
    expect(
      TrackTags.of(t),
      const TrackTags(
        title: 'New',
        artist: 'Artist',
        album: 'Album',
        albumArtist: 'Album Artist',
        genre: 'Genre',
        trackNumber: 3,
        discNumber: 1,
        year: 2020,
      ),
    );
    expect(t.contentHash, 'h1');
    expect(t.fileName, 'h1.mp3');
    expect(tracks.firstWhere((t) => t.id == ids.last).title, 'Other');

    await repo.updateTags({ids.first: const TrackTags()});
    final cleared = (await repo.watchAll().first).firstWhere(
      (t) => t.id == ids.first,
    );
    expect(TrackTags.of(cleared), const TrackTags());
  });

  test('updateTags writes coverFile for the given ids', () async {
    await repo.insert(row('h1', cover: 'old.jpg'));
    await repo.insert(row('h2', cover: 'old.jpg'));
    final ids = [for (final t in await repo.watchAll().first) t.id];

    await repo.updateTags(
      {ids.first: const TrackTags(), ids.last: const TrackTags()},
      coverFiles: {ids.first: 'new.jpg', ids.last: null},
    );

    final tracks = await repo.watchAll().first;
    expect(tracks.firstWhere((t) => t.id == ids.first).coverFile, 'new.jpg');
    expect(tracks.firstWhere((t) => t.id == ids.last).coverFile, isNull);
  });

  test('updateTags without coverFiles keeps the cover', () async {
    await repo.insert(row('h1', cover: 'old.jpg'));
    final id = (await repo.watchAll().first).single.id;
    await repo.updateTags({id: const TrackTags(title: 'T')});
    expect((await repo.watchAll().first).single.coverFile, 'old.jpg');
  });

  group('playlists', () {
    Future<int> addPlaylist(String name, {String? cover}) => db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: name,
            createdAt: DateTime(2026, 1, 1),
            coverFile: Value(cover),
          ),
        );

    Future<void> addEntry(int playlistId, int trackId, int position) => db
        .into(db.playlistEntries)
        .insert(
          PlaylistEntriesCompanion.insert(
            playlistId: playlistId,
            trackId: trackId,
            position: position,
          ),
        );

    test('delete removes the track from playlists and renumbers', () async {
      await repo.insert(row('h1'));
      await repo.insert(row('h2'));
      final tracks = await repo.watchAll().first;
      final t1 = tracks.firstWhere((t) => t.fileName == 'h1.mp3').id;
      final t2 = tracks.firstWhere((t) => t.fileName == 'h2.mp3').id;
      final p1 = await addPlaylist('A');
      final p2 = await addPlaylist('B');
      await addEntry(p1, t1, 0);
      await addEntry(p1, t2, 1);
      await addEntry(p1, t1, 2);
      await addEntry(p1, t2, 3);
      await addEntry(p2, t2, 0);

      await repo.delete(t1);

      final e1 = await (db.select(
        db.playlistEntries,
      )..where((e) => e.playlistId.equals(p1))).get();
      e1.sort((a, b) => a.position.compareTo(b.position));
      expect([for (final e in e1) e.trackId], [t2, t2]);
      expect([for (final e in e1) e.position], [0, 1]);
      final e2 = await (db.select(
        db.playlistEntries,
      )..where((e) => e.playlistId.equals(p2))).get();
      expect(e2.single.trackId, t2);
      expect(e2.single.position, 0);
    });

    test('delete keeps a cover a playlist still uses', () async {
      writeAudio('h1.mp3');
      writeCover('c1.jpg');
      await repo.insert(row('h1', cover: 'c1.jpg'));
      await addPlaylist('A', cover: 'c1.jpg');
      final id = (await repo.watchAll().first).single.id;

      await repo.delete(id);

      expect(storage.coverFile('c1.jpg').existsSync(), isTrue);
    });

    test('cleanupOrphans keeps playlist covers', () async {
      writeCover('p1.jpg');
      writeCover('stray.jpg');
      await addPlaylist('A', cover: 'p1.jpg');

      await repo.cleanupOrphans();

      expect(storage.coverFile('p1.jpg').existsSync(), isTrue);
      expect(storage.coverFile('stray.jpg').existsSync(), isFalse);
    });

    test('isCoverReferenced sees playlist covers', () async {
      await addPlaylist('A', cover: 'p1.jpg');

      expect(await repo.isCoverReferenced('p1.jpg'), isTrue);
      expect(await repo.isCoverReferenced('other.jpg'), isFalse);
    });
  });
}
