import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/src/rust/api/library.dart';

const supported = {'mp3', 'm4a', 'aac', 'flac', 'wav'};

ReadResult ok(
  String hash, {
  String? title,
  String? artist,
  String? album,
  CoverArt? cover,
}) {
  return ReadResult(
    status: ReadStatus.ok,
    track: TrackInfo(
      title: title,
      artist: artist,
      album: album,
      durationMs: 1000,
      contentHash: hash,
      cover: cover,
    ),
  );
}

CoverArt cover(String hash, {String ext = 'png'}) => CoverArt(
  data: Uint8List.fromList([1, 2, 3]),
  fileExtension: ext,
  hash: hash,
);

void main() {
  late Directory tmp;
  late Directory picked;
  late LibraryStorage storage;
  late AppDatabase db;
  late TrackRepository repo;
  // Canned results keyed by the file's content (the picked files contain
  // their own name), because the importer reads a renamed `.part` copy.
  late Map<String, ReadResult> results;
  late Set<String> throwing;

  Future<ReadResult> fakeRead(String path) async {
    final key = utf8.decode(File(path).readAsBytesSync());
    if (throwing.contains(key)) throw StateError('boom');
    return results[key] ?? const ReadResult(status: ReadStatus.unreadable);
  }

  Importer importer({Set<String> extensions = supported}) => Importer(
    repo: repo,
    storage: storage,
    read: fakeRead,
    supportedExtensions: extensions,
  );

  String pick(String name, {String? content}) {
    final file = File('${picked.path}/$name')
      ..writeAsStringSync(content ?? name);
    return file.path;
  }

  List<String> audioFiles() =>
      storage.audioDir.listSync().map((e) => e.uri.pathSegments.last).toList()
        ..sort();

  List<String> coverFiles() =>
      storage.coversDir.listSync().map((e) => e.uri.pathSegments.last).toList()
        ..sort();

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('owntune_import_test');
    picked = Directory('${tmp.path}/picked')..createSync();
    storage = LibraryStorage(Directory('${tmp.path}/library'));
    await storage.ensure();
    db = AppDatabase(NativeDatabase.memory());
    repo = TrackRepository(db, storage);
    results = {};
    throwing = {};
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('imports a supported file', () async {
    results['song.mp3'] = ok('h1', title: 'Song', artist: 'Ann');

    final summary = await importer().importFiles([pick('song.mp3')]);

    expect(summary.added, 1);
    expect(summary.duplicates, 0);
    expect(summary.unsupported, isEmpty);
    final rows = await repo.watchAll().first;
    expect(rows, hasLength(1));
    expect(rows.single.fileName, 'h1.mp3');
    expect(rows.single.originalName, 'song.mp3');
    expect(rows.single.title, 'Song');
    expect(rows.single.artist, 'Ann');
    expect(audioFiles(), ['h1.mp3']);
    expect(audioFiles().any((n) => n.contains('.part')), isFalse);
  });

  test(
    'extension matching is case-insensitive and lowercases the stored ext',
    () async {
      results['LOUD.MP3'] = ok('h1');

      final summary = await importer().importFiles([pick('LOUD.MP3')]);

      expect(summary.added, 1);
      expect(audioFiles(), ['h1.mp3']);
    },
  );

  test('same file twice in one batch -> 1 added, 1 duplicate', () async {
    results['a.mp3'] = ok('h1');
    results['b.mp3'] = ok('h1');
    final a = pick('a.mp3');
    final b = pick('b.mp3', content: 'a.mp3');

    final summary = await importer().importFiles([a, b]);

    expect(summary.added, 1);
    expect(summary.duplicates, 1);
    expect(summary.checked, 2);
    expect(audioFiles(), ['h1.mp3']);
  });

  test('a duplicate of an existing track leaves its files untouched', () async {
    results['a.mp3'] = ok('h1', cover: cover('c1'));
    await importer().importFiles([pick('a.mp3')]);
    final before = storage.audioFile('h1.mp3').lastModifiedSync();

    results['again.mp3'] = ok('h1', cover: cover('c1'));
    final summary = await importer().importFiles([pick('again.mp3')]);

    expect(summary.added, 0);
    expect(summary.duplicates, 1);
    expect(audioFiles(), ['h1.mp3']);
    expect(coverFiles(), ['c1.png']);
    expect(storage.audioFile('h1.mp3').lastModifiedSync(), before);
  });

  test('unsupported extension is not copied', () async {
    final summary = await importer().importFiles([pick('evening-walk.ogg')]);

    expect(summary.unsupported, ['evening-walk.ogg']);
    expect(summary.added, 0);
    expect(audioFiles(), isEmpty);
  });

  test('file without an extension is unsupported', () async {
    final summary = await importer().importFiles([pick('README')]);

    expect(summary.unsupported, ['README']);
    expect(audioFiles(), isEmpty);
  });

  test('unreadable file is reported and the batch continues', () async {
    results['good.mp3'] = ok('h1');
    final summary = await importer().importFiles([
      pick('broken.mp3'),
      pick('good.mp3'),
    ]);

    expect(summary.added, 1);
    expect(summary.unsupported, ['broken.mp3']);
    expect(audioFiles(), ['h1.mp3']);
  });

  test('reader status unsupported is reported like unreadable', () async {
    results['odd.mp3'] = const ReadResult(status: ReadStatus.unsupported);

    final summary = await importer().importFiles([pick('odd.mp3')]);

    expect(summary.unsupported, ['odd.mp3']);
    expect(audioFiles(), isEmpty);
  });

  test('reader throwing is treated like unreadable', () async {
    throwing.add('boom.mp3');
    results['good.mp3'] = ok('h1');

    final summary = await importer().importFiles([
      pick('boom.mp3'),
      pick('good.mp3'),
    ]);

    expect(summary.added, 1);
    expect(summary.unsupported, ['boom.mp3']);
    expect(audioFiles(), ['h1.mp3']);
  });

  group('failure reasons', () {
    test('an unreadable file keeps the reader message', () async {
      results['broken.mp3'] = const ReadResult(
        status: ReadStatus.unreadable,
        message: 'bad frame header',
      );
      final summary = await importer().importFiles([pick('broken.mp3')]);
      expect(summary.failures, [
        (name: 'broken.mp3', reason: 'bad frame header'),
      ]);
    });

    test('an unreadable file without message gets a generic reason', () async {
      final summary = await importer().importFiles([pick('broken.mp3')]);
      expect(summary.failures, [
        (name: 'broken.mp3', reason: 'Could not be read'),
      ]);
    });

    test('reader status unsupported says so', () async {
      results['odd.mp3'] = const ReadResult(status: ReadStatus.unsupported);
      final summary = await importer().importFiles([pick('odd.mp3')]);
      expect(summary.failures, [
        (name: 'odd.mp3', reason: 'Format not supported'),
      ]);
    });

    test('an exception keeps its text', () async {
      throwing.add('boom.mp3');
      final summary = await importer().importFiles([pick('boom.mp3')]);
      expect(summary.failures.single.name, 'boom.mp3');
      expect(summary.failures.single.reason, contains('boom'));
    });

    test('a missing source file names the copy error', () async {
      final summary = await importer().importFiles(['${picked.path}/gone.mp3']);
      expect(summary.failures.single.reason, contains('gone.mp3'));
    });

    test('an unsupported extension needs no reason', () async {
      final summary = await importer().importFiles([pick('evening-walk.ogg')]);
      expect(summary.unsupported, ['evening-walk.ogg']);
      expect(summary.failures, isEmpty);
    });
  });

  test('a missing source file is reported and the batch continues', () async {
    results['good.mp3'] = ok('h1');

    final summary = await importer().importFiles([
      '${picked.path}/gone.mp3',
      pick('good.mp3'),
    ]);

    expect(summary.added, 1);
    expect(summary.unsupported, ['gone.mp3']);
    expect(audioFiles(), ['h1.mp3']);
  });

  test('cover written once for two tracks with the same cover hash', () async {
    results['a.mp3'] = ok('h1', cover: cover('c1'));
    results['b.mp3'] = ok('h2', cover: cover('c1'));

    final summary = await importer().importFiles([
      pick('a.mp3'),
      pick('b.mp3'),
    ]);

    expect(summary.added, 2);
    expect(coverFiles(), ['c1.png']);
    final rows = await repo.watchAll().first;
    expect(rows.map((r) => r.coverFile), ['c1.png', 'c1.png']);
  });

  test('a track without a cover has no cover file', () async {
    results['a.mp3'] = ok('h1');

    await importer().importFiles([pick('a.mp3')]);

    expect(coverFiles(), isEmpty);
    expect((await repo.watchAll().first).single.coverFile, isNull);
  });

  test('progress reports each file and completion', () async {
    results['a.mp3'] = ok('h1');
    results['b.mp3'] = ok('h2');
    results['c.mp3'] = ok('h3');
    final events = <ImportProgress>[];

    await importer().importFiles([
      pick('a.mp3'),
      pick('b.mp3'),
      pick('c.mp3'),
    ], onProgress: events.add);

    expect(events.map((e) => e.done), [0, 1, 2, 3]);
    expect(events.every((e) => e.total == 3), isTrue);
    expect(events.take(3).map((e) => e.currentName), [
      'a.mp3',
      'b.mp3',
      'c.mp3',
    ]);
  });

  test('albums and artists counted among added tracks', () async {
    results['a.mp3'] = ok('h1', artist: 'Ann', album: 'One');
    results['b.mp3'] = ok('h2', artist: 'Ann', album: 'One');
    results['c.mp3'] = ok('h3', artist: 'Bob', album: 'Two');
    results['d.mp3'] = ok('h4', artist: 'Cy'); // no album
    results['e.mp3'] = ok('h5'); // Unknown Artist, no album
    results['dup.mp3'] = ok('h1', artist: 'Zed', album: 'Ignored');

    final summary = await importer().importFiles([
      pick('a.mp3'),
      pick('b.mp3'),
      pick('c.mp3'),
      pick('d.mp3'),
      pick('e.mp3'),
      pick('dup.mp3'),
    ]);

    expect(summary.added, 5);
    expect(summary.duplicates, 1);
    expect(summary.albums, 2);
    expect(summary.artists, 4); // Ann, Bob, Cy, Unknown Artist
  });

  test('a second importFiles while one is pending throws StateError', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final slow = Importer(
      repo: repo,
      storage: storage,
      read: (path) async {
        if (!started.isCompleted) started.complete();
        await gate.future;
        return fakeRead(path);
      },
      supportedExtensions: supported,
    );
    results['a.mp3'] = ok('h1');
    results['b.mp3'] = ok('h2');

    final first = slow.importFiles([pick('a.mp3')]);
    await started.future;

    await expectLater(
      slow.importFiles([pick('b.mp3')]),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'An import is already running',
        ),
      ),
    );

    gate.complete();
    final summary = await first;
    expect(summary.added, 1);
    expect(audioFiles(), ['h1.mp3']);

    // The importer is usable again afterwards.
    results['b.mp3'] = ok('h2');
    expect((await slow.importFiles([pick('b.mp3')])).added, 1);
  });

  group('rollback', () {
    test('failed insert removes only what this attempt created', () async {
      // Existing row owns the cover c1 and audio h1.mp3.
      results['a.mp3'] = ok('h1', cover: cover('c1'));
      await importer().importFiles([pick('a.mp3')]);

      // The insert of h3 fails; b.mp3 (h2) imports normally.
      final failing = _FailingRepo(db, storage, failOn: 'h3.mp3');
      results['b.mp3'] = ok('h2', cover: cover('c1'));
      results['c.mp3'] = ok('h3', cover: cover('c3'));

      final summary = await Importer(
        repo: failing,
        storage: storage,
        read: fakeRead,
        supportedExtensions: supported,
      ).importFiles([pick('c.mp3'), pick('b.mp3')]);

      // c.mp3: insert failed -> its audio and its freshly written cover are
      // gone. b.mp3: imported, shares the existing cover c1.
      expect(summary.unsupported, ['c.mp3']);
      expect(summary.added, 1);
      expect(audioFiles(), ['h1.mp3', 'h2.mp3']);
      expect(coverFiles(), ['c1.png']);
    });

    test(
      'failed insert never deletes a cover owned by an existing row',
      () async {
        results['a.mp3'] = ok('h1', cover: cover('c1'));
        await importer().importFiles([pick('a.mp3')]);

        final failing = _FailingRepo(db, storage, failOn: 'h2.mp3');
        results['b.mp3'] = ok('h2', cover: cover('c1'));

        final summary = await Importer(
          repo: failing,
          storage: storage,
          read: fakeRead,
          supportedExtensions: supported,
        ).importFiles([pick('b.mp3')]);

        expect(summary.unsupported, ['b.mp3']);
        expect(audioFiles(), ['h1.mp3']);
        expect(coverFiles(), ['c1.png']);
      },
    );

    test(
      'insert losing a race keeps the audio file of the existing row',
      () async {
        results['a.mp3'] = ok('h1');
        await importer().importFiles([pick('a.mp3')]);

        // hasHash reports "free" although a row with this hash exists, as if
        // that row had been inserted by a concurrent attempt after the check.
        final racing = _FailingRepo(db, storage, hasHashFalseOnce: true);
        results['b.mp3'] = ok('h1');
        final summary = await Importer(
          repo: racing,
          storage: storage,
          read: fakeRead,
          supportedExtensions: supported,
        ).importFiles([pick('b.mp3')]);

        expect(summary.added, 0);
        expect(summary.unsupported, ['b.mp3']);
        expect(audioFiles(), ['h1.mp3']);
        expect(storage.audioFile('h1.mp3').existsSync(), isTrue);
        expect(await repo.count(), 1);
      },
    );

    test('hasHash throwing does not touch existing library files', () async {
      results['a.mp3'] = ok('h1');
      await importer().importFiles([pick('a.mp3')]);

      final failing = _FailingRepo(db, storage, failHasHash: true);
      results['b.mp3'] = ok('h1');
      final summary = await Importer(
        repo: failing,
        storage: storage,
        read: fakeRead,
        supportedExtensions: supported,
      ).importFiles([pick('b.mp3')]);

      expect(summary.unsupported, ['b.mp3']);
      expect(audioFiles(), ['h1.mp3']);
    });
  });
}

class _FailingRepo extends TrackRepository {
  _FailingRepo(
    super.db,
    super.storage, {
    this.failOn,
    this.failHasHash = false,
    this.hasHashFalseOnce = false,
  });

  final String? failOn;
  final bool failHasHash;
  bool hasHashFalseOnce;

  @override
  Future<bool> hasHash(String hash) async {
    if (failHasHash) throw StateError('hasHash failed');
    if (hasHashFalseOnce) {
      hasHashFalseOnce = false;
      return false;
    }
    return super.hasHash(hash);
  }

  @override
  Future<void> insert(TracksCompanion row) async {
    if (row.fileName.value == failOn) throw StateError('insert failed');
    return super.insert(row);
  }
}
