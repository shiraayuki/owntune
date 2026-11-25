import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/mp4_duration.dart';
import 'package:owntune/download/stream_download.dart';

import '../support/fakes.dart';
import '../support/mp4_boxes.dart';

const mib = 1 << 20;

void main() {
  late Directory tmp;
  late File target;
  final bytes = List<int>.generate(24 * mib, (i) => i % 251);
  final stream = RangedStream(
    url: Uri.parse('https://example.invalid/videoplayback?itag=140'),
    contentLength: bytes.length,
    extension: 'm4a',
    bitrate: 128000,
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('owntune_stream_test');
    target = File('${tmp.path}/audio.part.m4a');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> download(FakeHttpTransport http, {CancelToken? cancel}) =>
      downloadStream(
        http,
        stream,
        target,
        onProgress: (_, _) {},
        cancel: cancel ?? CancelToken(),
      );

  test('downloads in 10 MB range chunks', () async {
    final http = FakeHttpTransport(onGet: serveRanges(bytes));
    final progress = <int>[];
    await downloadStream(
      http,
      stream,
      target,
      onProgress: (received, total) {
        expect(total, 24 * mib);
        progress.add(received);
      },
      cancel: CancelToken(),
    );
    expect(http.gets.map((u) => u.queryParameters['range']), [
      '0-${10 * mib - 1}',
      '${10 * mib}-${20 * mib - 1}',
      '${20 * mib}-${24 * mib - 1}',
    ]);
    expect(http.gets.first.queryParameters['itag'], '140');
    expect(target.readAsBytesSync(), bytes);
    expect(progress.last, 24 * mib);
  });

  test('HTTP 403 on the second chunk throws '
      '"Download failed: HTTP 403 after 10.0 of 24.0 MB"', () async {
    final http = FakeHttpTransport(
      onGet: serveRanges(bytes, status: (i) => i == 1 ? 403 : 200),
    );
    await expectLater(
      download(http),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          'Download failed: HTTP 403 after 10.0 of 24.0 MB',
        ),
      ),
    );
  });

  test('short responses continue from the received offset', () async {
    final http = FakeHttpTransport(
      onGet: serveRanges(bytes, maxPerResponse: 7 * mib),
    );
    await download(http);
    expect(http.gets.map((u) => u.queryParameters['range']).take(2), [
      '0-${10 * mib - 1}',
      '${7 * mib}-${17 * mib - 1}',
    ]);
    expect(target.readAsBytesSync(), bytes);
  });

  test(
    'a connection lost mid-file says how far it got, without the URL',
    () async {
      final http = FakeHttpTransport(
        onGet: (url, headers) async => HttpBody(
          200,
          Stream.fromIterable([List.filled(mib, 1)]).followedBy(
            const HttpException(
              'Connection closed while receiving data, '
              'uri = https://rr1.example.invalid/videoplayback?ip=1.2.3.4',
            ),
          ),
        ),
      );
      await expectLater(
        download(http),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            'Download stopped at 1.0 of 24.0 MB (connection lost)',
          ),
        ),
      );
    },
  );

  test('an empty chunk throws "Download stopped at…"', () async {
    final http = FakeHttpTransport(
      onGet: (url, headers) async => HttpBody(200, const Stream.empty()),
    );
    await expectLater(
      download(http),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          'Download stopped at 0.0 of 24.0 MB',
        ),
      ),
    );
  });

  test('cancel throws DownloadCancelled', () async {
    final cancel = CancelToken();
    final http = FakeHttpTransport(
      onGet: (url, headers) async {
        cancel.cancel();
        return HttpBody(200, Stream.value(List.filled(1024, 1)));
      },
    );
    await expectLater(
      download(http, cancel: cancel),
      throwsA(isA<DownloadCancelled>()),
    );
  });

  test('a cancel while the server is silent ends the download', () async {
    final cancel = CancelToken();
    final http = FakeHttpTransport(
      onGet: (url, headers) async => HttpBody(
        200,
        Stream<List<int>>.periodic(const Duration(hours: 1), (_) => [1]),
      ),
    );
    final done = download(http, cancel: cancel);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cancel.cancel();
    await expectLater(done, throwsA(isA<DownloadCancelled>()));
  });

  Map<String, Object?> checkpoint() =>
      jsonDecode(File('${target.path}.progress').readAsStringSync())
          as Map<String, Object?>;

  group('ranged resume', () {
    test(
      'a ranged stream resumes from the checkpoint with the next range',
      () async {
        await expectLater(
          download(
            FakeHttpTransport(
              onGet: serveRanges(bytes, status: (i) => i == 1 ? 403 : 200),
            ),
          ),
          throwsA(isA<OnlineError>()),
        );
        expect(checkpoint(), {
          'shape': 'ranged:${bytes.length}',
          'bytes': 10 * mib,
          'done': 10 * mib,
        });
        // A chunk that died half way leaves bytes after the checkpoint.
        target.writeAsBytesSync(List.filled(100, 7), mode: FileMode.append);

        final http = FakeHttpTransport(onGet: serveRanges(bytes));
        await download(http);
        expect(http.gets.map((u) => u.queryParameters['range']), [
          '${10 * mib}-${20 * mib - 1}',
          '${20 * mib}-${24 * mib - 1}',
        ]);
        expect(target.readAsBytesSync(), bytes);
      },
    );

    test('a ranged stream with another content length starts over', () async {
      await expectLater(
        download(
          FakeHttpTransport(
            onGet: serveRanges(bytes, status: (i) => i == 1 ? 403 : 200),
          ),
        ),
        throwsA(isA<OnlineError>()),
      );
      final other = List<int>.generate(20 * mib, (i) => (i + 5) % 251);
      final http = FakeHttpTransport(onGet: serveRanges(other));
      await downloadStream(
        http,
        RangedStream(
          url: stream.url,
          contentLength: other.length,
          extension: 'm4a',
          bitrate: 128000,
        ),
        target,
        onProgress: (_, _) {},
        cancel: CancelToken(),
      );
      expect(http.gets.first.queryParameters['range'], '0-${10 * mib - 1}');
      expect(target.readAsBytesSync(), other);
    });
  });

  group('segmented', () {
    // A real init, padded so that its length is a multiple of 12: then the
    // extrapolated total is exact after 1 to 5 of 5 segments.
    final initBytes = () {
      final base = mp4();
      final pad = (12 - (base.length + 8) % 12) % 12;
      return Uint8List.fromList([...base, ...box('free', List.filled(pad, 0))]);
    }();
    List<int> segData(int i) => List.generate(1000, (j) => (i * 37 + j) % 251);
    const segDuration = Duration(seconds: 10);

    SegmentedStream segStream(int n) => SegmentedStream(
      initUrl: Uri.parse('https://example.invalid/init.mp4?sig=SECRET'),
      segments: [
        for (var i = 0; i < n; i++)
          HlsSegment(
            Uri.parse('https://example.invalid/seg$i.mp4?sig=SECRET'),
            segDuration,
          ),
      ],
      bitrate: 160000,
    );
    Map<String, List<int>> serve(int n) => {
      '/init.mp4': initBytes,
      for (var i = 0; i < n; i++) '/seg$i.mp4': segData(i),
    };

    /// The file for [n] segments of which [written] are in it.
    List<int> expected(int n, [int? written]) => [
      ...patchMp4Duration(initBytes, segDuration * n),
      for (var i = 0; i < (written ?? n); i++) ...segData(i),
    ];

    Future<void> downloadSeg(
      FakeHttpTransport http, {
      int n = 5,
      CancelToken? cancel,
      void Function(int, int)? onProgress,
    }) => downloadStream(
      http,
      segStream(n),
      target,
      onProgress: onProgress ?? (_, _) {},
      cancel: cancel ?? CancelToken(),
    );

    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 5000 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(condition(), isTrue, reason: 'timed out');
    }

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 30));

    test('a segmented stream writes the patched init and then every segment '
        'in order', () async {
      await downloadSeg(FakeHttpTransport(onGet: serveSegments(serve(5))));
      expect(target.readAsBytesSync(), expected(5));
      expect(checkpoint(), {
        'shape': 'segmented:5:${initBytes.length}',
        'bytes': expected(5).length,
        'done': 5,
      });
    });

    test(
      'fetches at most 4 segments at once and still writes in order',
      () async {
        final gates = {
          for (var i = 0; i < 5; i++) '/seg$i.mp4': Completer<void>(),
        };
        final answer = serveSegments(serve(5));
        var inFlight = 0;
        var most = 0;
        final http = FakeHttpTransport(
          onGet: (url, headers) async {
            final gate = gates[url.path];
            if (gate != null) {
              most = max(most, ++inFlight);
              await gate.future;
              inFlight--;
            }
            return answer(url, headers);
          },
        );
        final run = downloadSeg(http);
        await until(() => http.gets.length == 5);
        await settle();
        expect(http.gets.map((u) => u.path), [
          '/init.mp4',
          '/seg0.mp4',
          '/seg1.mp4',
          '/seg2.mp4',
          '/seg3.mp4',
        ]);
        // The newest segments arrive first; seg0 holds the window.
        for (final i in [3, 2, 1]) {
          gates['/seg$i.mp4']!.complete();
        }
        await settle();
        expect(http.gets, hasLength(5), reason: 'seg4 waits for the window');
        gates['/seg0.mp4']!.complete();
        await until(() => http.gets.length == 6);
        gates['/seg4.mp4']!.complete();
        await run;
        expect(most, 4);
        expect(target.readAsBytesSync(), expected(5));
      },
    );

    test('progress is segment-based', () async {
      final progress = <(int, int)>[];
      await downloadSeg(
        FakeHttpTransport(onGet: serveSegments(serve(5))),
        onProgress: (r, t) => progress.add((r, t)),
      );
      final n = expected(5).length;
      expect(progress.last, (n, n));
      // The first call is the init, before any segment: only an estimate.
      expect(progress.first.$2, segStream(5).estimatedBytes);
      expect(progress, hasLength(6));
      for (var k = 1; k <= 5; k++) {
        final (received, total) = progress[k];
        expect(received / total, closeTo(k / 5, 1e-9));
      }
    });

    test('an HTTP 403 on segment 3 fails with "Download failed: HTTP 403 '
        'after …" and leaves a checkpoint with done=3', () async {
      final http = FakeHttpTransport(
        onGet: serveSegments(
          serve(5),
          status: (path) => path == '/seg3.mp4' ? 403 : 200,
        ),
      );
      await expectLater(
        downloadSeg(http),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            allOf(
              startsWith('Download failed: HTTP 403 after '),
              endsWith(' MB'),
              isNot(contains('SECRET')),
            ),
          ),
        ),
      );
      expect(checkpoint()['done'], 3);
      expect(checkpoint()['bytes'], expected(5, 3).length);
      expect(target.readAsBytesSync(), expected(5, 3));
    });

    test('a connection lost in a segment says how far it got, without the '
        'URL', () async {
      final answer = serveSegments(serve(5));
      final http = FakeHttpTransport(
        onGet: (url, headers) async => url.path == '/seg1.mp4'
            ? HttpBody(
                200,
                Stream<List<int>>.error(HttpException('closed, uri = $url')),
              )
            : answer(url, headers),
      );
      await expectLater(
        downloadSeg(http),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            allOf(
              startsWith('Download stopped at '),
              endsWith(' MB (connection lost)'),
              isNot(contains('SECRET')),
            ),
          ),
        ),
      );
      expect(checkpoint()['done'], 1);
    });

    test('resume continues after the checkpoint and fetches only the missing '
        'segments', () async {
      await expectLater(
        downloadSeg(
          FakeHttpTransport(
            onGet: serveSegments(
              serve(5),
              status: (path) => path == '/seg3.mp4' ? 403 : 200,
            ),
          ),
        ),
        throwsA(isA<OnlineError>()),
      );
      final http = FakeHttpTransport(onGet: serveSegments(serve(5)));
      await downloadSeg(http);
      expect(
        http.gets.map((u) => u.path),
        unorderedEquals(['/init.mp4', '/seg3.mp4', '/seg4.mp4']),
      );
      expect(target.readAsBytesSync(), expected(5));
    });

    test('a partly written segment is cut off before continuing', () async {
      await expectLater(
        downloadSeg(
          FakeHttpTransport(
            onGet: serveSegments(
              serve(5),
              status: (path) => path == '/seg3.mp4' ? 403 : 200,
            ),
          ),
        ),
        throwsA(isA<OnlineError>()),
      );
      target.writeAsBytesSync(List.filled(100, 7), mode: FileMode.append);
      await downloadSeg(FakeHttpTransport(onGet: serveSegments(serve(5))));
      expect(target.readAsBytesSync(), expected(5));
    });

    test('a different shape starts over', () async {
      await expectLater(
        downloadSeg(
          FakeHttpTransport(
            onGet: serveSegments(
              serve(5),
              status: (path) => path == '/seg3.mp4' ? 403 : 200,
            ),
          ),
        ),
        throwsA(isA<OnlineError>()),
      );
      final http = FakeHttpTransport(onGet: serveSegments(serve(6)));
      await downloadSeg(http, n: 6);
      expect(
        http.gets.map((u) => u.path),
        unorderedEquals([
          '/init.mp4',
          for (var i = 0; i < 6; i++) '/seg$i.mp4',
        ]),
      );
      expect(target.readAsBytesSync(), expected(6));
    });

    test('cancel with requests in flight stops at once and the checkpoint '
        'matches the file length', () async {
      final gates = {
        for (var i = 2; i < 5; i++) '/seg$i.mp4': Completer<void>(),
      };
      final answer = serveSegments(serve(5));
      final http = FakeHttpTransport(
        onGet: (url, headers) async {
          await gates[url.path]?.future;
          return answer(url, headers);
        },
      );
      final cancel = CancelToken();
      final atTwo = expected(5, 2).length;
      final run = downloadSeg(
        http,
        cancel: cancel,
        onProgress: (received, _) {
          if (received >= atTwo) cancel.cancel();
        },
      );
      await expectLater(run, throwsA(isA<DownloadCancelled>()));
      // The late answers must not land in the file.
      for (final gate in gates.values) {
        gate.complete();
      }
      await settle();
      expect(target.lengthSync(), atTwo);
      expect(checkpoint()['bytes'], atTwo);
      expect(checkpoint()['done'], 2);
      expect(target.readAsBytesSync(), expected(5, 2));
    });
  });
}

extension<T> on Stream<T> {
  /// This stream, then [error].
  Stream<T> followedBy(Object error) async* {
    yield* this;
    throw error;
  }
}
