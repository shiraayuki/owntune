import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';

void main() {
  late HttpServer server;
  late int status;
  late String body;
  late Map<String, String> redirects;
  late List<String> requested;

  setUp(() async {
    status = 200;
    body = '{"ok":true}';
    server = await HttpServer.bind('127.0.0.1', 0);
    redirects = {};
    requested = [];
    server.listen((req) async {
      await req.drain<void>();
      requested.add(req.uri.path);
      final to = redirects[req.uri.path];
      if (to != null) {
        req.response.statusCode = HttpStatus.found;
        req.response.headers.set(HttpHeaders.locationHeader, to);
        await req.response.close();
        return;
      }
      req.response.statusCode = status;
      req.response.write(body);
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri url() => Uri.parse('http://127.0.0.1:${server.port}/x');

  test('getJson returns the JSON object', () async {
    expect(await IoHttpTransport().getJson(url(), service: 'SoundCloud'), {
      'ok': true,
    });
  });

  test('getJson on a 500 throws HttpStatusError with "SoundCloud didn\'t answer: HTTP 500"', () async {
    status = 500;
    await expectLater(
      IoHttpTransport().getJson(url(), service: 'SoundCloud'),
      throwsA(
        isA<HttpStatusError>()
            .having((e) => e.service, 'service', 'SoundCloud')
            .having((e) => e.statusCode, 'statusCode', 500)
            .having(
              (e) => e.message,
              'message',
              "SoundCloud didn't answer: HTTP 500",
            ),
      ),
    );
  });

  test('getJson on an HTML body throws "SoundCloud changed something; '
      'owntune needs an update"', () async {
    body = '<html>consent</html>';
    await expectLater(
      IoHttpTransport().getJson(url(), service: 'SoundCloud'),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          'SoundCloud changed something; owntune needs an update',
        ),
      ),
    );
  });

  test('postJson keeps naming YouTube by default', () async {
    status = 429;
    await expectLater(
      IoHttpTransport().postJson(url(), {}),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          "YouTube didn't answer: HTTP 429",
        ),
      ),
    );
  });

  group('finalUrl', () {
    test('returns the URL itself without a redirect', () async {
      expect(await IoHttpTransport().finalUrl(url()), url());
    });

    test('follows absolute and relative Location headers', () async {
      redirects = {'/a': '/b', '/b': 'http://127.0.0.1:${server.port}/c'};
      final end = await IoHttpTransport().finalUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a'),
      );
      expect(end, Uri.parse('http://127.0.0.1:${server.port}/c'));
      expect(requested, ['/a', '/b', '/c']);
    });

    test('stops after five hops', () async {
      redirects = {for (var i = 0; i < 10; i++) '/$i': '/${i + 1}'};
      final end = await IoHttpTransport().finalUrl(
        Uri.parse('http://127.0.0.1:${server.port}/0'),
      );
      expect(end.path, '/5');
      expect(requested, ['/0', '/1', '/2', '/3', '/4', '/5']);
    });
  });
}
