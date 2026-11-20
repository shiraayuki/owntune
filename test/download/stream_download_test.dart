import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/stream_download.dart';

import '../support/fakes.dart';

const mib = 1 << 20;

void main() {
  late Directory tmp;
  late File target;
  final bytes = List<int>.generate(24 * mib, (i) => i % 251);
  final stream = ResolvedStream(
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
}

extension<T> on Stream<T> {
  /// This stream, then [error].
  Stream<T> followedBy(Object error) async* {
    yield* this;
    throw error;
  }
}
