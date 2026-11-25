import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/youtube/youtube_sources.dart';

import '../../support/fakes.dart';

Map<String, Object?> fixture(String name) =>
    jsonDecode(File('test/fixtures/online/$name.json').readAsStringSync())
        as Map<String, Object?>;

Map<String, Object?> withVisitor(Map<String, Object?> json, String visitor) => {
  ...json,
  'responseContext': {
    ...json['responseContext']! as Map<String, Object?>,
    'visitorData': visitor,
  },
};

void main() {
  late FakeHttpTransport http;
  late YoutubeSources sources;

  setUp(() {
    http = FakeHttpTransport(
      onPost: (url, body) => switch (url.path) {
        '/youtubei/v1/search' when url.host == 'music.youtube.com' =>
          withVisitor(fixture('ytmusic_search'), 'V-music'),
        '/youtubei/v1/search' => withVisitor(
          fixture('youtube_search'),
          'V-web',
        ),
        '/youtubei/v1/player' => fixture('player_ok'),
        _ => throw StateError('unexpected $url'),
      },
    );
    sources = YoutubeSources(http);
  });

  test('resolve sends VISIONOS headers and the visitorData from the last '
      'search', () async {
    final rows = await sources.video.search('linkin park numb');
    final stream = await sources.video.resolve(rows.first);

    expect((stream as RangedStream).contentLength, 3037787);
    final player = http.posts.last;
    expect(
      player.url.toString(),
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
    );
    expect(player.headers['X-YouTube-Client-Name'], '101');
    expect(player.headers['X-YouTube-Client-Version'], '1.02');
    expect(player.headers['X-Goog-Visitor-Id'], 'V-web');
    expect(player.headers['Origin'], 'https://www.youtube.com');
    expect(player.headers['User-Agent'], contains('Safari'));
    final client = (player.body['context']! as Map)['client']! as Map;
    expect(client['clientName'], 'VISIONOS');
    expect(client['clientVersion'], '1.02');
    expect(client['visitorData'], 'V-web');
    expect(player.body['videoId'], 'kXYiU_JCYtU');
    expect(player.body['contentCheckOk'], isTrue);
    expect(player.body['racyCheckOk'], isTrue);
  });

  test('music search uses WEB_REMIX with the songs filter', () async {
    final rows = await sources.music.search('linkin park numb');
    expect(rows.first.title, 'Numb');
    final search = http.posts.single;
    expect(search.url.host, 'music.youtube.com');
    expect(search.body['query'], 'linkin park numb');
    expect(search.body['params'], 'EgWKAQIIAWoKEAoQAxAEEAkQBQ==');
    final client = (search.body['context']! as Map)['client']! as Map;
    expect(client['clientName'], 'WEB_REMIX');
  });

  test('resolve before any search fetches visitorData first', () async {
    final rows = await YoutubeSources(
      FakeHttpTransport(
        onPost: (url, body) => withVisitor(fixture('ytmusic_search'), 'x'),
      ),
    ).music.search('numb');
    http.posts.clear();

    await sources.music.resolve(rows.first);

    expect(http.posts.map((p) => p.url.path), [
      '/youtubei/v1/search',
      '/youtubei/v1/player',
    ]);
    expect(http.posts.last.headers['X-Goog-Visitor-Id'], 'V-music');
  });

  group('IoHttpTransport', () {
    late HttpServer server;
    late int status;

    setUp(() async {
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>();
        req.response.statusCode = status;
        req.response.write('{"ok":true}');
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Uri url() => Uri.parse('http://127.0.0.1:${server.port}/x');

    test('returns the JSON body', () async {
      expect(await IoHttpTransport().postJson(url(), {}), {'ok': true});
    });

    test('HTTP 429 becomes "YouTube didn\'t answer: HTTP 429"', () async {
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

    test(
      'a 200 that is not JSON becomes "YouTube changed something"',
      () async {
        server.close(force: true);
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((req) async {
          await req.drain<void>();
          req.response.write('<html>consent</html>');
          await req.response.close();
        });
        await expectLater(
          IoHttpTransport().postJson(url(), {}),
          throwsA(
            isA<OnlineError>().having(
              (e) => e.message,
              'message',
              'YouTube changed something; owntune needs an update',
            ),
          ),
        );
      },
    );

    test('a server that never answers becomes "No connection"', () async {
      server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>(); // and never respond
      });
      final transport = IoHttpTransport(
        timeout: const Duration(milliseconds: 200),
      );
      await expectLater(
        transport.postJson(url(), {}),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            'No connection',
          ),
        ),
      );
      await expectLater(
        transport.get(url()),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            'No connection',
          ),
        ),
      );
    });

    test('a refused connection becomes "No connection"', () async {
      final port = server.port;
      await server.close(force: true);
      await expectLater(
        IoHttpTransport().postJson(Uri.parse('http://127.0.0.1:$port/x'), {}),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            'No connection',
          ),
        ),
      );
    });
  });
}
