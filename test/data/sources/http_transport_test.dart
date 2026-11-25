import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';

void main() {
  late HttpServer server;
  late int status;
  late String body;

  setUp(() async {
    status = 200;
    body = '{"ok":true}';
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      await req.drain<void>();
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
}
