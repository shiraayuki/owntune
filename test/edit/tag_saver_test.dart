import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/edit/tag_saver.dart';
import 'package:owntune/edit/track_tags.dart';

import '../support/fakes.dart';

void main() {
  late FakeTrackRepository repo;
  late FakeTagWriter writer;
  late TagSaver saver;
  late Directory tmp;
  late LibraryStorage storage;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('owntune_tag_saver_test');
    storage = LibraryStorage(tmp);
    await storage.ensure();
    repo = FakeTrackRepository();
    writer = FakeTagWriter();
    saver = TagSaver(
      write: writer.call,
      storage: storage,
      repo: repo,
      hash: (_) => 'h1',
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  final a = track(1, title: 'A', album: 'Old');
  final b = track(2, title: 'B', album: 'Old');

  test('writes the file, then the row', () async {
    final failures = await saver.save([
      a,
    ], const TagEdit({TagField.album: 'New'}));
    expect(failures, isEmpty);
    expect(writer.written.keys, [storage.audioFile('hash1.mp3').path]);
    expect(writer.written.values.single.album, 'New');
    expect(writer.written.values.single.title, 'A');
    expect(repo.updatedTags, [
      {1: const TrackTags(title: 'A', album: 'New')},
    ]);
  });

  test('a failed write leaves its row unchanged and is reported', () async {
    writer.failing[storage.audioFile('hash2.mp3').path] = 'read-only file';
    final failures = await saver.save([
      a,
      b,
    ], const TagEdit({TagField.album: 'New'}));
    expect(failures, hasLength(1));
    expect(failures.single.track.id, 2);
    expect(failures.single.message, 'read-only file');
    expect(repo.updatedTags.single.keys, [1]);
  });

  test('a write that throws is reported too', () async {
    writer.throwing = true;
    final failures = await saver.save([
      a,
    ], const TagEdit({TagField.album: 'X'}));
    expect(failures.single.track.id, 1);
    expect(repo.updatedTags, isEmpty);
  });

  test('unchanged songs are not written', () async {
    final failures = await saver.save([
      a,
    ], const TagEdit({TagField.album: 'Old'}));
    expect(failures, isEmpty);
    expect(writer.written, isEmpty);
    expect(repo.updatedTags, isEmpty);
  });

  test('rows of one save are updated in one call', () async {
    await saver.save([a, b], const TagEdit({TagField.genre: 'Folk'}));
    expect(repo.updatedTags, hasLength(1));
    expect(repo.updatedTags.single.keys, [1, 2]);
  });

  group('covers', () {
    final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 1, 2]);
    const jpeg = 'image/jpeg';
    String path(int id) => storage.audioFile('hash$id.mp3').path;

    test('set writes the cover into every file and stores it once', () async {
      final failures = await saver.save([
        a,
        b,
      ], TagEdit({}, cover: CoverSet(bytes, jpeg)));
      expect(failures, isEmpty);
      expect(writer.covers[path(1)], isA<CoverSet>());
      expect(writer.covers[path(2)], isA<CoverSet>());
      expect(storage.coverFile('h1.jpg').readAsBytesSync(), bytes);
      expect(repo.updatedCovers.single, {1: 'h1.jpg', 2: 'h1.jpg'});
      expect(repo.updatedTags.single.keys, [1, 2]);
    });

    test('png covers are stored as .png', () async {
      await saver.save([a], TagEdit({}, cover: CoverSet(bytes, 'image/png')));
      expect(storage.coverFile('h1.png').existsSync(), isTrue);
      expect(repo.updatedCovers.single, {1: 'h1.png'});
    });

    test('a failed file keeps its row and its cover', () async {
      writer.failing[path(2)] = 'read-only file';
      final failures = await saver.save([
        a,
        b,
      ], TagEdit({}, cover: CoverSet(bytes, jpeg)));
      expect(failures.single.track.id, 2);
      expect(repo.updatedCovers.single, {1: 'h1.jpg'});
    });

    test('remove skips songs without cover', () async {
      final withCover = track(1, title: 'A', cover: 'a.jpg');
      final without = track(2, title: 'B');
      await saver.save([
        withCover,
        without,
      ], const TagEdit({}, cover: CoverRemove()));
      expect(writer.covers.keys, [path(1)]);
      expect(writer.covers[path(1)], isA<CoverRemove>());
      expect(repo.updatedCovers.single, {1: null});
    });

    test('remove on a song without cover still saves its tag change', () async {
      await saver.save([
        a,
      ], const TagEdit({TagField.genre: 'Folk'}, cover: CoverRemove()));
      expect(writer.covers[path(1)], isA<CoverKeep>());
      expect(repo.updatedCovers.single, isEmpty);
    });

    test('tag-only edits pass CoverKeep', () async {
      await saver.save([a], const TagEdit({TagField.genre: 'Folk'}));
      expect(writer.covers[path(1)], isA<CoverKeep>());
      expect(repo.updatedCovers.single, isEmpty);
    });

    test('old cover file is deleted when nothing references it', () async {
      storage.coverFile('a.jpg').writeAsBytesSync([1]);
      final old = track(1, title: 'A', cover: 'a.jpg');
      await saver.save([old], TagEdit({}, cover: CoverSet(bytes, jpeg)));
      expect(storage.coverFile('a.jpg').existsSync(), isFalse);
    });

    test('old cover file is kept while another row references it', () async {
      storage.coverFile('a.jpg').writeAsBytesSync([1]);
      repo.referencedCovers.add('a.jpg');
      final old = track(1, title: 'A', cover: 'a.jpg');
      await saver.save([old], const TagEdit({}, cover: CoverRemove()));
      expect(storage.coverFile('a.jpg').existsSync(), isTrue);
    });

    test(
      'the new cover file is deleted again when no file was written',
      () async {
        writer.failing[path(1)] = 'nope';
        writer.failing[path(2)] = 'nope';
        await saver.save([a, b], TagEdit({}, cover: CoverSet(bytes, jpeg)));
        expect(storage.coverFile('h1.jpg').existsSync(), isFalse);
        expect(repo.updatedTags, isEmpty);
      },
    );

    test('an existing cover file is not touched or deleted', () async {
      storage.coverFile('h1.jpg').writeAsBytesSync([7]);
      writer.throwing = true;
      await saver.save([a], TagEdit({}, cover: CoverSet(bytes, jpeg)));
      expect(storage.coverFile('h1.jpg').readAsBytesSync(), [7]);
    });
  });
}
