import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/download_controller.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/download/mp4_duration.dart';
import 'package:owntune/edit/track_tags.dart';
import 'package:owntune/import/importer.dart';

import '../support/fakes.dart';
import '../support/mp4_boxes.dart';

/// Imports immediately; remembers each file's name and content and the
/// source keys it was given.
class _InstantImporter implements Importer {
  final imported = <({String name, List<int> bytes, String? sourceKey})>[];
  ImportSummary Function(String path)? answer;

  @override
  Future<ImportSummary> importFiles(
    List<String> paths, {
    void Function(ImportProgress)? onProgress,
    Map<String, String> sourceKeys = const {},
  }) async {
    final path = paths.single;
    imported.add((
      name: path.split('/').last,
      bytes: File(path).readAsBytesSync(),
      sourceKey: sourceKeys[path],
    ));
    return answer?.call(path) ??
        const ImportSummary(
          added: 1,
          duplicates: 0,
          unsupported: [],
          albums: 1,
          artists: 1,
        );
  }
}

const _audio = [1, 2, 3, 4];

void main() {
  late Directory tmp;
  late FakeOnlineSource music;
  late FakeHttpTransport http;
  late FakeDownloadTagWriter writer;
  late Importer importer;
  late ProviderContainer container;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('owntune_download_test');
    music = FakeOnlineSource(OnlineSourceId.ytmusic);
    writer = FakeDownloadTagWriter();
    importer = _InstantImporter();
    final cover = img.encodeJpg(img.Image(width: 8, height: 8));
    http = FakeHttpTransport(
      onGet: (url, headers) async => url.path.startsWith('/cover/')
          ? HttpBody(200, Stream.value(cover))
          : await serveRanges(_audio)(url, headers),
    );
  });

  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  DownloadController start() {
    container = ProviderContainer(
      overrides: [
        onlineSourcesProvider.overrideWithValue({
          OnlineSourceId.ytmusic: music,
          OnlineSourceId.youtube: FakeOnlineSource(OnlineSourceId.youtube),
        }),
        httpTransportProvider.overrideWithValue(http),
        downloadTagWriterProvider.overrideWithValue(writer.call),
        importerProvider.overrideWith((ref) => importer),
        downloadDirProvider.overrideWithValue(() async => tmp),
      ],
    );
    return container.read(downloadControllerProvider.notifier);
  }

  List<DownloadJob> jobs() => container.read(downloadControllerProvider);

  Future<void> settle() async {
    for (var i = 0; i < 500 && jobs().any((j) => j.isActive); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(jobs().where((j) => j.isActive), isEmpty, reason: 'still active');
  }

  _InstantImporter instant() => importer as _InstantImporter;

  test('a job goes waiting → downloading → importing → done and passes the '
      'source key', () async {
    final controller = start();
    final phases = <DownloadPhase>[];
    container.listen(downloadControllerProvider, (_, next) {
      final phase = next.single.phase;
      if (phases.isEmpty || phases.last != phase) phases.add(phase);
    }, fireImmediately: false);

    controller.enqueue(
      onlineResult('abc'),
      const TrackTags(title: 'Numb', artist: 'Linkin Park', album: 'Meteora'),
    );
    await settle();

    expect(phases, [
      DownloadPhase.waiting,
      DownloadPhase.downloading,
      DownloadPhase.importing,
      DownloadPhase.done,
    ]);
    final job = jobs().single;
    expect(job.received, 4);
    expect(job.total, 4);
    final imported = instant().imported.single;
    expect(imported.name, 'Linkin Park - Numb.m4a');
    expect(imported.bytes, _audio);
    expect(imported.sourceKey, 'youtube:abc');
    expect(writer.calls.single.tags.album, 'Meteora');
    expect(writer.calls.single.cover?.mime, 'image/jpeg');
    expect(writer.calls.single.path, endsWith('.m4a'));
    expect(tmp.listSync(), isEmpty);
  });

  test('jobs run one at a time in order', () async {
    final controller = start();
    final gate = Completer<void>();
    final order = <String>[];
    http.onGet = (url, headers) async {
      if (url.path.startsWith('/cover/')) {
        return HttpBody(404, const Stream.empty());
      }
      order.add(url.path);
      if (order.length == 1) await gate.future;
      return serveRanges(_audio)(url, headers);
    };
    controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
    controller.enqueue(onlineResult('b'), const TrackTags(title: 'B'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(order, ['/audio/a']);
    expect(jobs().map((j) => j.phase), [
      DownloadPhase.downloading,
      DownloadPhase.waiting,
    ]);
    gate.complete();
    await settle();
    expect(order, ['/audio/a', '/audio/b']);
    expect(instant().imported.map((i) => i.name), ['A.m4a', 'B.m4a']);
  });

  test('enqueue twice with the same sourceKey makes one job', () async {
    final controller = start();
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    controller.enqueue(
      onlineResult('abc', source: OnlineSourceId.youtube),
      const TrackTags(title: 'Numb'),
    );
    expect(jobs(), hasLength(1));
    await settle();
    expect(instant().imported, hasLength(1));
  });

  test('a failed download keeps its folder, nothing imported', () async {
    final controller = start();
    http.onGet = (url, headers) async => HttpBody(403, const Stream.empty());
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    final job = jobs().single;
    expect(job.phase, DownloadPhase.failed);
    expect(job.error, 'Download failed: HTTP 403 after 0.0 of 0.0 MB');
    expect(instant().imported, isEmpty);
    expect(tmp.listSync(), hasLength(1));
  });

  test('a resolve error fails the job with its message', () async {
    final controller = start();
    music.resolveError = const OnlineError('YouTube: Video unavailable');
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.failed);
    expect(jobs().single.error, 'YouTube: Video unavailable');
  });

  test('cancel while downloading keeps the folder', () async {
    final controller = start();
    http.onGet = (url, headers) async => HttpBody(
      200,
      Stream<List<int>>.periodic(const Duration(hours: 1), (_) => [1]),
    );
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(jobs().single.phase, DownloadPhase.downloading);
    controller.cancel(jobs().single.id);
    await settle();
    expect(jobs().single.phase, DownloadPhase.cancelled);
    expect(instant().imported, isEmpty);
    expect(tmp.listSync(), hasLength(1));
  });

  test(
    'cancel while the cover is fetched → cancelled, nothing added',
    () async {
      final controller = start();
      final coverAsked = Completer<void>();
      http.onGet = (url, headers) async {
        if (url.path.startsWith('/cover/')) {
          coverAsked.complete();
          return Completer<HttpBody>().future; // never answers
        }
        return serveRanges(_audio)(url, headers);
      };
      controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
      await coverAsked.future;
      expect(jobs().single.phase, DownloadPhase.downloading);
      controller.cancel(jobs().single.id);
      await settle();
      expect(jobs().single.phase, DownloadPhase.cancelled);
      expect(writer.calls, isEmpty);
      expect(instant().imported, isEmpty);
      expect(tmp.listSync(), hasLength(1));
    },
  );

  test('cancel during the tag write → cancelled, nothing added', () async {
    final controller = start();
    final gate = Completer<void>();
    final writing = Completer<void>();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        onlineSourcesProvider.overrideWithValue({
          OnlineSourceId.ytmusic: music,
          OnlineSourceId.youtube: FakeOnlineSource(OnlineSourceId.youtube),
        }),
        httpTransportProvider.overrideWithValue(http),
        downloadTagWriterProvider.overrideWithValue((path, tags, cover) async {
          writing.complete();
          await gate.future;
          return null;
        }),
        importerProvider.overrideWith((ref) => importer),
        downloadDirProvider.overrideWithValue(() async => tmp),
      ],
    );
    final c2 = container.read(downloadControllerProvider.notifier);
    expect(controller, isNot(same(c2)));
    c2.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await writing.future;
    c2.cancel(jobs().single.id);
    gate.complete();
    await settle();
    expect(jobs().single.phase, DownloadPhase.cancelled);
    expect(instant().imported, isEmpty);
    // The tags changed the file, so the checkpoint no longer describes it: a
    // retry must start over instead of cutting the file back.
    final folder = tmp.listSync().single as Directory;
    expect(folder.listSync().map((f) => f.path.split('/').last), [
      'audio.part.m4a',
    ]);
  });

  test('cancel of a waiting job never starts it', () async {
    final controller = start();
    final gate = Completer<void>();
    http.onGet = (url, headers) async {
      await gate.future;
      return serveRanges(_audio)(url, headers);
    };
    controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
    controller.enqueue(onlineResult('b'), const TrackTags(title: 'B'));
    controller.cancel(jobs().last.id);
    gate.complete();
    await settle();
    expect(jobs().map((j) => j.phase), [
      DownloadPhase.done,
      DownloadPhase.cancelled,
    ]);
    expect(music.resolved, ['a']);
  });

  test('retry re-queues at the end', () async {
    final controller = start();
    music.resolveError = const OnlineError('No connection');
    controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
    await settle();
    music.resolveError = null;
    final failed = jobs().single;
    controller.retry(failed.id);
    // Queued again and started at once (nothing else is running).
    expect(jobs().single.isActive, isTrue);
    expect(jobs().single.error, isNull);
    await settle();
    expect(jobs().single.phase, DownloadPhase.done);
  });

  test('retry does nothing once the song was queued again (its failed job '
      'is dropped)', () async {
    final controller = start();
    music.resolveError = const OnlineError('No connection');
    controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
    await settle();
    music.resolveError = null;
    final failed = jobs().single;
    controller
      ..enqueue(onlineResult('b'), const TrackTags(title: 'B'))
      ..enqueue(onlineResult('a'), const TrackTags(title: 'A'));
    controller.retry(failed.id);
    expect(jobs().where((j) => j.id == failed.id), isEmpty);
    expect(
      jobs().where((j) => j.isActive && j.result.sourceKey == 'youtube:a'),
      hasLength(1),
    );
    await settle();
  });

  test('a failing cover still adds the song without cover', () async {
    final controller = start();
    http.onGet = (url, headers) async => url.path.startsWith('/cover/')
        ? HttpBody(200, Stream.value([9, 9, 9]))
        : await serveRanges(_audio)(url, headers);
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.done);
    expect(writer.calls.single.cover, isNull);
  });

  test('a cover that cannot be fetched still adds the song', () async {
    final controller = start();
    http.onGet = (url, headers) async {
      if (url.path.startsWith('/cover/')) {
        throw const OnlineError('No connection');
      }
      return serveRanges(_audio)(url, headers);
    };
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.done);
    expect(writer.calls.single.cover, isNull);
  });

  test('a tag write error fails the job', () async {
    final controller = start();
    writer.error = 'disk full';
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.failed);
    // The sheet adds "Couldn't download: ", so no second "Couldn't" here.
    expect(jobs().single.error, 'The tags could not be written: disk full');
    expect(instant().imported, isEmpty);
    expect(tmp.listSync(), hasLength(1));
  });

  test('a tag write failure, then retry, does not download again', () async {
    final controller = start();
    final audioGets = <Uri>[];
    final serve = serveRanges(_audio);
    http.onGet = (url, headers) async {
      if (url.path.startsWith('/cover/')) {
        return HttpBody(404, const Stream.empty());
      }
      audioGets.add(url);
      return serve(url, headers);
    };
    writer.error = 'disk full';
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.failed);
    expect(audioGets, hasLength(1));

    writer.error = null;
    controller.retry(jobs().single.id);
    await settle();
    expect(jobs().single.phase, DownloadPhase.done);
    expect(audioGets, hasLength(1), reason: 'no range GET on the retry');
    expect(instant().imported.single.bytes, _audio);
    expect(tmp.listSync(), isEmpty);
  });

  test('retry after a failure continues the download', () async {
    final controller = start();
    final audio = List.generate(15 << 20, (i) => i % 251);
    music.streams['abc'] = RangedStream(
      url: Uri.parse('https://example.invalid/audio/abc'),
      contentLength: audio.length,
      extension: 'm4a',
      bitrate: 128000,
    );
    final ranges = <String>[];
    var serve = serveRanges(audio, status: (i) => i == 1 ? 500 : 200);
    http.onGet = (url, headers) async {
      if (url.path.startsWith('/cover/')) {
        return HttpBody(404, const Stream.empty());
      }
      ranges.add(url.queryParameters['range']!);
      return serve(url, headers);
    };
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.failed);
    expect(
      jobs().single.error,
      'Download failed: HTTP 500 after 10.0 of 15.0 MB',
    );
    expect(ranges, ['0-${(10 << 20) - 1}', '${10 << 20}-${audio.length - 1}']);

    ranges.clear();
    serve = serveRanges(audio);
    controller.retry(jobs().single.id);
    await settle();
    expect(jobs().single.phase, DownloadPhase.done);
    expect(ranges, ['${10 << 20}-${audio.length - 1}']);
    expect(instant().imported.single.bytes, audio);
    expect(tmp.listSync(), isEmpty);
  });

  test('a 403 halfway, then retry with a fresh resolve, continues', () async {
    final controller = start();
    final base = mp4();
    final pad = (12 - (base.length + 8) % 12) % 12;
    final init = Uint8List.fromList([
      ...base,
      ...box('free', List.filled(pad, 0)),
    ]);
    List<int> segData(int i) => List.generate(1000, (j) => (i * 37 + j) % 251);
    const segDuration = Duration(seconds: 10);
    SegmentedStream signed(String sig) => SegmentedStream(
      initUrl: Uri.parse('https://example.invalid/init.mp4?sig=$sig'),
      segments: [
        for (var i = 0; i < 5; i++)
          HlsSegment(
            Uri.parse('https://example.invalid/seg$i.mp4?sig=$sig'),
            segDuration,
          ),
      ],
      bitrate: 160000,
    );
    final files = {
      '/init.mp4': init,
      for (var i = 0; i < 5; i++) '/seg$i.mp4': segData(i),
    };
    music.streams['abc'] = signed('old');
    final paths = <String>[];
    var serve = serveSegments(
      files,
      status: (path) => path == '/seg3.mp4' ? 403 : 200,
    );
    http.onGet = (url, headers) async {
      if (url.path.startsWith('/cover/')) {
        return HttpBody(404, const Stream.empty());
      }
      paths.add('${url.path}?${url.query}');
      return serve(url, headers);
    };
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.failed);
    expect(jobs().single.error, startsWith('Download failed: HTTP 403 after '));
    expect(
      paths.where((p) => p.contains('seg4') || p.contains('seg3')),
      isNotEmpty,
    );

    // The signed URLs expired: the retry resolves again and gets new ones.
    paths.clear();
    music.streams['abc'] = signed('new');
    serve = serveSegments(files);
    controller.retry(jobs().single.id);
    await settle();
    expect(jobs().single.phase, DownloadPhase.done);
    expect(music.resolved, ['abc', 'abc']);
    expect(
      paths,
      unorderedEquals([
        '/init.mp4?sig=new',
        '/seg3.mp4?sig=new',
        '/seg4.mp4?sig=new',
      ]),
    );
    expect(instant().imported.single.bytes, [
      ...patchMp4Duration(init, segDuration * 5),
      for (var i = 0; i < 5; i++) ...segData(i),
    ]);
    expect(tmp.listSync(), isEmpty);
  });

  test('done and duplicate delete the folder before the job shows as '
      'finished', () async {
    final controller = start();
    // The folder state at the moment each job turns done or duplicate.
    final foldersLeft = <DownloadPhase, int>{};
    container.listen(downloadControllerProvider, (_, next) {
      for (final j in next) {
        if (j.phase == DownloadPhase.done ||
            j.phase == DownloadPhase.duplicate) {
          foldersLeft[j.phase] = tmp.listSync().length;
        }
      }
    });
    controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.done);
    expect(foldersLeft[DownloadPhase.done], 0);
    expect(tmp.listSync(), isEmpty);

    instant().answer = (_) => const ImportSummary(
      added: 0,
      duplicates: 1,
      unsupported: [],
      albums: 0,
      artists: 0,
    );
    controller.enqueue(onlineResult('b'), const TrackTags(title: 'B'));
    await settle();
    expect(jobs().last.phase, DownloadPhase.duplicate);
    expect(foldersLeft[DownloadPhase.duplicate], 0);
    expect(tmp.listSync(), isEmpty);
  });

  group('a checkpoint that cannot be deleted after the tag write', () {
    test('the part file goes too, and the job fails readably', () async {
      final controller = start();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          onlineSourcesProvider.overrideWithValue({
            OnlineSourceId.ytmusic: music,
            OnlineSourceId.youtube: FakeOnlineSource(OnlineSourceId.youtube),
          }),
          httpTransportProvider.overrideWithValue(http),
          downloadTagWriterProvider.overrideWithValue((
            path,
            tags,
            cover,
          ) async {
            // A directory with content cannot be deleted as a file.
            final progress = File('$path.progress')..deleteSync();
            Directory(progress.path).createSync();
            File('${progress.path}/x').writeAsStringSync('x');
            return null;
          }),
          importerProvider.overrideWith((ref) => importer),
          downloadDirProvider.overrideWithValue(() async => tmp),
        ],
      );
      expect(controller, isNotNull);
      container
          .read(downloadControllerProvider.notifier)
          .enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
      await settle();

      expect(jobs().single.phase, DownloadPhase.failed);
      expect(
        jobs().single.error,
        'The download could not be finished. Try again to start over.',
      );
      expect(instant().imported, isEmpty);
      final folder = tmp.listSync().single as Directory;
      expect(
        folder.listSync().map((f) => f.path.split('/').last),
        isNot(contains('audio.part.m4a')),
      );
    });

    test('when the part file cannot be deleted either, a retry uses a fresh '
        'folder and downloads again', () async {
      final controller = start();
      final locked = <Directory>[];
      container.dispose();
      container = ProviderContainer(
        overrides: [
          onlineSourcesProvider.overrideWithValue({
            OnlineSourceId.ytmusic: music,
            OnlineSourceId.youtube: FakeOnlineSource(OnlineSourceId.youtube),
          }),
          httpTransportProvider.overrideWithValue(http),
          downloadTagWriterProvider.overrideWithValue((
            path,
            tags,
            cover,
          ) async {
            if (locked.isEmpty) {
              final folder = File(path).parent;
              Process.runSync('chmod', ['555', folder.path]);
              locked.add(folder);
            }
            return null;
          }),
          importerProvider.overrideWith((ref) => importer),
          downloadDirProvider.overrideWithValue(() async => tmp),
        ],
      );
      expect(controller, isNotNull);
      final c = container.read(downloadControllerProvider.notifier);
      addTearDown(() {
        for (final d in locked) {
          Process.runSync('chmod', ['755', d.path]);
        }
      });
      c.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
      await settle();
      expect(jobs().single.phase, DownloadPhase.failed);
      expect(
        jobs().single.error,
        'The download could not be finished. Try again to start over.',
      );
      // The old folder still holds the tagged part file and its checkpoint.
      final old = locked.single;
      expect(File('${old.path}/audio.part.m4a').existsSync(), isTrue);

      c.retry(jobs().single.id);
      await settle();
      expect(jobs().single.phase, DownloadPhase.done);
      expect(instant().imported.single.bytes, _audio);
      // The retry did not touch the old folder.
      expect(File('${old.path}/audio.part.m4a').existsSync(), isTrue);
    });
  });

  group('enqueue for a song that has inactive jobs', () {
    test('drops its failed job and deletes the folder', () async {
      final controller = start();
      http.onGet = (url, headers) async => HttpBody(500, const Stream.empty());
      controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
      await settle();
      expect(jobs().single.phase, DownloadPhase.failed);
      final oldId = jobs().single.id;
      final oldFolder = tmp.listSync().single.path;

      http.onGet = (url, headers) async => url.path.startsWith('/cover/')
          ? HttpBody(404, const Stream.empty())
          : await serveRanges(_audio)(url, headers);
      controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
      expect(jobs(), hasLength(1));
      expect(jobs().single.id, isNot(oldId));
      await settle();
      expect(jobs().single.phase, DownloadPhase.done);
      expect(tmp.listSync().map((f) => f.path), isNot(contains(oldFolder)));
      expect(tmp.listSync(), isEmpty);
    });

    test('drops its cancelled job and deletes the folder', () async {
      final controller = start();
      http.onGet = (url, headers) async => HttpBody(
        200,
        Stream<List<int>>.periodic(const Duration(hours: 1), (_) => [1]),
      );
      controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.cancel(jobs().single.id);
      await settle();
      expect(jobs().single.phase, DownloadPhase.cancelled);
      final oldFolder = tmp.listSync().single.path;

      http.onGet = (url, headers) async => HttpBody(500, const Stream.empty());
      controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
      expect(jobs(), hasLength(1));
      await settle();
      expect(jobs().single.phase, DownloadPhase.failed);
      expect(tmp.listSync().map((f) => f.path), isNot(contains(oldFolder)));
    });

    test('keeps its done and duplicate jobs', () async {
      final controller = start();
      controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
      await settle();
      instant().answer = (_) => const ImportSummary(
        added: 0,
        duplicates: 1,
        unsupported: [],
        albums: 0,
        artists: 0,
      );
      controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
      await settle();
      expect(jobs().map((j) => j.phase), [
        DownloadPhase.done,
        DownloadPhase.duplicate,
      ]);
    });

    test('leaves the jobs of other songs alone', () async {
      final controller = start();
      http.onGet = (url, headers) async => HttpBody(500, const Stream.empty());
      controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
      await settle();
      controller.enqueue(onlineResult('b'), const TrackTags(title: 'B'));
      await settle();
      expect(jobs().map((j) => j.result.id), ['a', 'b']);
      expect(tmp.listSync(), hasLength(2));
    });
  });

  test(
    'a progress total of 0 shows no percent and does not fail the job',
    () async {
      final controller = start();
      final base = mp4();
      final pad = (12 - (base.length + 8) % 12) % 12;
      final init = Uint8List.fromList([
        ...base,
        ...box('free', List.filled(pad, 0)),
      ]);
      // Zero-length segments: the estimated size, and so the total, is 0.
      music.streams['abc'] = SegmentedStream(
        initUrl: Uri.parse('https://example.invalid/init.mp4'),
        segments: [
          for (var i = 0; i < 2; i++)
            HlsSegment(
              Uri.parse('https://example.invalid/seg$i.mp4'),
              Duration.zero,
            ),
        ],
        bitrate: 160000,
      );
      final serve = serveSegments({
        '/init.mp4': init,
        '/seg0.mp4': [1, 2, 3],
        '/seg1.mp4': [4, 5, 6],
      });
      http.onGet = (url, headers) async => url.path.startsWith('/cover/')
          ? HttpBody(404, const Stream.empty())
          : serve(url, headers);
      final totals = <int>[];
      container.listen(downloadControllerProvider, (_, next) {
        totals.add(next.single.total);
      });
      controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
      await settle();
      expect(jobs().single.phase, DownloadPhase.done);
      expect(jobs().single.error, isNull);
      expect(totals.where((t) => t > 0), isNotEmpty);
    },
  );

  test('clearFinished deletes the folders of the jobs it drops and keeps '
      'active ones', () async {
    final controller = start();
    http.onGet = (url, headers) async => HttpBody(500, const Stream.empty());
    controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.failed);
    final failedFolder = tmp.listSync().single;

    // A second job stays active (its download never answers).
    http.onGet = (url, headers) async => HttpBody(
      200,
      Stream<List<int>>.periodic(const Duration(hours: 1), (_) => [1]),
    );
    controller.enqueue(onlineResult('b'), const TrackTags(title: 'B'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(jobs().last.phase, DownloadPhase.downloading);
    expect(tmp.listSync(), hasLength(2));

    controller.clearFinished();
    expect(jobs().map((j) => j.result.id), ['b']);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      tmp.listSync().map((f) => f.path),
      isNot(contains(failedFolder.path)),
    );
    expect(tmp.listSync(), hasLength(1));

    controller.cancel(jobs().single.id);
    await settle();
  });

  test('"AC/DC - What?" is imported as AC_DC - What_.m4a with the exact '
      'tags', () async {
    final controller = start();
    const tags = TrackTags(title: 'What?', artist: 'AC/DC');
    controller.enqueue(onlineResult('abc'), tags);
    await settle();
    expect(instant().imported.single.name, 'AC_DC - What_.m4a');
    expect(writer.calls.single.tags, tags);
  });

  test('a very long title is cut to a short file name', () async {
    final controller = start();
    controller.enqueue(onlineResult('abc'), TrackTags(title: 'x' * 300));
    await settle();
    expect(instant().imported.single.name, '${'x' * 120}.m4a');
  });

  test(
    'a duplicate import ends as duplicate "Already in your library"',
    () async {
      final controller = start();
      instant().answer = (_) => const ImportSummary(
        added: 0,
        duplicates: 1,
        unsupported: [],
        albums: 0,
        artists: 0,
      );
      controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
      await settle();
      expect(jobs().single.phase, DownloadPhase.duplicate);
      expect(jobs().single.error, 'Already in your library');
    },
  );

  test('an import failure fails the job with its reason', () async {
    final controller = start();
    instant().answer = (path) => ImportSummary(
      added: 0,
      duplicates: 0,
      unsupported: [path.split('/').last],
      failures: [(name: path.split('/').last, reason: 'Could not be read')],
      albums: 0,
      artists: 0,
    );
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.failed);
    expect(jobs().single.error, 'Could not be read');
  });

  test('waits for a running Import Music and then succeeds', () async {
    final fake = FakeImporter();
    importer = fake;
    final controller = start();
    final running = fake.importFiles(['/picked/a.mp3']);
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(jobs().single.phase, DownloadPhase.importing);
    expect(fake.calls, hasLength(1));

    fake.finish(summary47);
    await running;
    await Future<void>.delayed(Duration.zero);
    expect(fake.calls, hasLength(2));
    expect(fake.sourceKeys.last.values, ['youtube:abc']);
    fake.finish(
      const ImportSummary(
        added: 1,
        duplicates: 0,
        unsupported: [],
        albums: 1,
        artists: 1,
      ),
    );
    await settle();
    expect(jobs().single.phase, DownloadPhase.done);
  });

  test('clearFinished keeps active jobs only', () async {
    final controller = start();
    final gate = Completer<void>();
    music.resolveError = const OnlineError('No connection');
    controller.enqueue(onlineResult('a'), const TrackTags(title: 'A'));
    await settle();
    music.resolveError = null;
    http.onGet = (url, headers) async {
      await gate.future;
      return serveRanges(_audio)(url, headers);
    };
    controller.enqueue(onlineResult('b'), const TrackTags(title: 'B'));
    controller.clearFinished();
    expect(jobs().map((j) => j.result.id), ['b']);
    gate.complete();
    await settle();
  });

  test('the default download folder is owntune\'s own', () async {
    start(); // tearDown disposes the container
    final dir = await defaultDownloadDir(temp: () async => Directory('/tmp'));
    expect(dir.path, '/tmp/owntune-download');
  });

  group('downloadFileName', () {
    for (final (name, title) in [
      ('Japanese', 'あ' * 100),
      ('emoji', '😀' * 100),
    ]) {
      test('a long $name title fits 200 UTF-8 bytes on whole characters', () {
        start(); // tearDown disposes the container
        final file = downloadFileName(TrackTags(title: title));
        expect(utf8.encode(file).length, lessThanOrEqualTo(200));
        expect(file, isNotEmpty);
        expect(title.startsWith(file), isTrue);
        expect(utf8.decode(utf8.encode(file)), file); // no lone surrogate
      });
    }
  });
}
