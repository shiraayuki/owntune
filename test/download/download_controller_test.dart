import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/download_controller.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/edit/track_tags.dart';
import 'package:owntune/import/importer.dart';

import '../support/fakes.dart';

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

  test('a failed download leaves no folder and no import', () async {
    final controller = start();
    http.onGet = (url, headers) async => HttpBody(403, const Stream.empty());
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    final job = jobs().single;
    expect(job.phase, DownloadPhase.failed);
    expect(job.error, 'Download failed: HTTP 403 after 0.0 of 0.0 MB');
    expect(instant().imported, isEmpty);
    expect(tmp.listSync(), isEmpty);
  });

  test('a resolve error fails the job with its message', () async {
    final controller = start();
    music.resolveError = const OnlineError('YouTube: Video unavailable');
    controller.enqueue(onlineResult('abc'), const TrackTags(title: 'Numb'));
    await settle();
    expect(jobs().single.phase, DownloadPhase.failed);
    expect(jobs().single.error, 'YouTube: Video unavailable');
  });

  test('cancel while downloading → cancelled, folder gone', () async {
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
    expect(tmp.listSync(), isEmpty);
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
      expect(tmp.listSync(), isEmpty);
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
    expect(tmp.listSync(), isEmpty);
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
    expect(jobs().single.error, "Couldn't write the tags: disk full");
    expect(instant().imported, isEmpty);
    expect(tmp.listSync(), isEmpty);
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
    expect(jobs().map((j) => j.result.videoId), ['b']);
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
