import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_link.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_api.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_client.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_parsers.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_source.dart';

import '../../support/fakes.dart';

String text(String name) =>
    File('test/fixtures/online/$name').readAsStringSync();

Map<String, Object?> json(String name) =>
    jsonDecode(text('$name.json')) as Map<String, Object?>;

HttpBody body(String content, [int status = 200]) =>
    HttpBody(status, Stream.value(utf8.encode(content)));

const fixtureId = 'FIXTURECLIENTIDFIXTURECLIENTID00';
const flipId = '2443730886';

final scriptUrls = [
  for (final m in scriptSrcPattern.allMatches(text('soundcloud_home.html')))
    m.group(1)!,
];
final lastScript = scriptUrls.last;

void main() {
  late FakeHttpTransport http;
  late MemorySoundcloudClientIdStore store;
  late SoundcloudSource source;
  late List<Map<String, String>> sentHeaders;

  /// Serves the home page, the scripts and the API like SoundCloud does;
  /// [onApi] answers `api-v2` calls, [scriptWithId] is the script that
  /// holds the client_id.
  void serve({
    required HttpBody Function(Uri url) onApi,
    String? scriptWithId,
    Duration delay = Duration.zero,
  }) {
    http.onGet = (url, headers) async {
      sentHeaders.add(headers);
      await Future<void>.delayed(delay);
      if (url.host == 'soundcloud.com') {
        return body(text('soundcloud_home.html'));
      }
      if (url.host == 'a-v2.sndcdn.com') {
        return body(
          url.toString() == scriptWithId
              ? text('soundcloud_script.js')
              : 'console.log("no id here")',
        );
      }
      if (url.host == 'api-v2.soundcloud.com') return onApi(url);
      if (url.path.endsWith('.m3u8')) {
        return body(text('soundcloud_playlist.m3u8'));
      }
      throw StateError('unexpected $url');
    };
  }

  HttpBody searchApi(Uri url) => body(text('soundcloud_search.json'));

  setUp(() {
    http = FakeHttpTransport();
    store = MemorySoundcloudClientIdStore();
    source = SoundcloudSource(SoundcloudClient(http, store));
    sentHeaders = [];
  });

  test('first search scrapes the client_id from the last script that has '
      'one and stores it', () async {
    final second = scriptUrls[scriptUrls.length - 2];
    serve(onApi: searchApi, scriptWithId: second);

    final rows = await source.search('linkin park numb');

    expect(rows, hasLength(20));
    expect(http.gets.map((u) => u.toString()), [
      'https://soundcloud.com/',
      lastScript,
      second,
      startsWith('https://api-v2.soundcloud.com/search/tracks?'),
    ]);
    final api = http.gets.last;
    expect(api.queryParameters, {
      'q': 'linkin park numb',
      'client_id': fixtureId,
      'limit': '20',
      'app_locale': 'en',
    });
    expect(store.id, fixtureId);
    expect(
      sentHeaders.every((h) => h['User-Agent'] == soundcloudUserAgent),
      isTrue,
    );
  });

  test('a stored client_id is used without scraping', () async {
    store.id = 'STOREDCLIENTIDSTOREDCLIENTID0000';
    serve(onApi: searchApi);

    await source.search('numb');
    await source.search('numb again');

    expect(http.gets, hasLength(2));
    expect(http.gets.every((u) => u.host == 'api-v2.soundcloud.com'), isTrue);
    expect(
      http.gets.first.queryParameters['client_id'],
      'STOREDCLIENTIDSTOREDCLIENTID0000',
    );
  });

  test('a 401 scrapes a new id once and repeats the request once', () async {
    store.id = 'STALECLIENTIDSTALECLIENTID000000';
    serve(
      scriptWithId: lastScript,
      onApi: (url) => url.queryParameters['client_id'] == fixtureId
          ? body(text('soundcloud_search.json'))
          : body('', 401),
    );

    final rows = await source.search('numb');

    expect(rows, hasLength(20));
    expect(http.gets.map((u) => u.host), [
      'api-v2.soundcloud.com',
      'soundcloud.com',
      'a-v2.sndcdn.com',
      'api-v2.soundcloud.com',
    ]);
    expect(store.id, fixtureId);
    // The new id is kept for the next call.
    await source.search('numb');
    expect(http.gets, hasLength(5));
  });

  test('a 403 is treated like a 401', () async {
    store.id = 'STALECLIENTIDSTALECLIENTID000000';
    serve(
      scriptWithId: lastScript,
      onApi: (url) => url.queryParameters['client_id'] == fixtureId
          ? body(text('soundcloud_search.json'))
          : body('', 403),
    );
    expect(await source.search('numb'), hasLength(20));
  });

  test(
    'a second 401 fails with "SoundCloud didn\'t answer: HTTP 401"',
    () async {
      store.id = 'STALECLIENTIDSTALECLIENTID000000';
      serve(scriptWithId: lastScript, onApi: (url) => body('', 401));

      await expectLater(
        source.search('numb'),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            "SoundCloud didn't answer: HTTP 401",
          ),
        ),
      );
      // search, home, script, search: no third try.
      expect(http.gets, hasLength(4));
    },
  );

  test('another status does not scrape', () async {
    store.id = 'STOREDCLIENTIDSTOREDCLIENTID0000';
    serve(onApi: (url) => body('', 429));
    await expectLater(
      source.search('numb'),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          "SoundCloud didn't answer: HTTP 429",
        ),
      ),
    );
    expect(http.gets, hasLength(1));
  });

  test('two searches at once scrape once', () async {
    serve(
      scriptWithId: lastScript,
      onApi: searchApi,
      delay: const Duration(milliseconds: 1),
    );

    final rows = await Future.wait([source.search('a'), source.search('b')]);

    expect(rows[0], hasLength(20));
    expect(http.gets.where((u) => u.host == 'soundcloud.com'), hasLength(1));
    expect(
      http.gets.where((u) => u.host == 'api-v2.soundcloud.com'),
      hasLength(2),
    );
  });

  test(
    'a script that answers non-200 is skipped; the next one is tried',
    () async {
      final second = scriptUrls[scriptUrls.length - 2];
      serve(onApi: searchApi, scriptWithId: second);
      final inner = http.onGet!;
      http.onGet = (url, headers) async => url.toString() == lastScript
          ? body('gone', 404)
          : inner(url, headers);

      final rows = await source.search('numb');

      expect(rows, hasLength(20));
      expect(store.id, fixtureId);
      expect(http.gets.map((u) => u.toString()), contains(second));
    },
  );

  test('every script non-200 still fails as changed', () async {
    serve(onApi: searchApi);
    final inner = http.onGet!;
    http.onGet = (url, headers) async =>
        url.host == 'a-v2.sndcdn.com' ? body('gone', 500) : inner(url, headers);

    await expectLater(
      source.search('numb'),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          'SoundCloud changed something; owntune needs an update',
        ),
      ),
    );
  });

  test('a malformed byte in a script is not a FormatException', () async {
    serve(onApi: searchApi);
    final inner = http.onGet!;
    final good = utf8.encode(text('soundcloud_script.js'));
    http.onGet = (url, headers) async => url.toString() == lastScript
        ? HttpBody(200, Stream.value([0xff, 0xfe, ...good]))
        : inner(url, headers);

    final rows = await source.search('numb');

    expect(rows, hasLength(20));
    expect(store.id, fixtureId);
  });

  test('no client_id in any script fails as changed', () async {
    serve(onApi: searchApi);

    await expectLater(
      source.search('numb'),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          'SoundCloud changed something; owntune needs an update',
        ),
      ),
    );
    expect(http.gets, hasLength(1 + scriptUrls.length));
    expect(store.id, isNull);
  });

  group('resolve', () {
    late OnlineResult flip;

    setUp(() async {
      store.id = fixtureId;
    });

    void serveTrack(Map<String, Object?> track) {
      final transcoding = pickTranscoding(track)?.url;
      serve(
        onApi: (url) {
          if (url.path == '/tracks/$flipId' ||
              url.path.startsWith('/tracks/')) {
            return body(jsonEncode(track));
          }
          if (url.toString().startsWith(transcoding.toString())) {
            return body(text('soundcloud_stream.json'));
          }
          return body(text('soundcloud_search.json'));
        },
      );
    }

    test('fetches the track again, picks the transcoding, calls it with '
        'client_id and track_authorization, and returns a SegmentedStream '
        'with 19 segments, bitrate 160000', () async {
      final track = json('soundcloud_track');
      serveTrack(track);
      flip = parseSoundcloudTrack(track);

      final stream = await source.resolve(flip);

      expect(stream, isA<SegmentedStream>());
      final segmented = stream as SegmentedStream;
      expect(segmented.segments, hasLength(19));
      expect(segmented.bitrate, 160000);
      expect(segmented.extension, 'm4a');
      expect(segmented.initUrl.path, endsWith('/init.mp4'));
      expect(segmented.total.inMilliseconds, closeTo(188848, 1));

      expect(http.gets.map((u) => u.path), [
        '/tracks/$flipId',
        endsWith('/stream/hls'),
        endsWith('/playlist.m3u8'),
      ]);
      expect(http.gets[0].queryParameters['client_id'], fixtureId);
      expect(http.gets[1].queryParameters, {
        'client_id': fixtureId,
        'track_authorization': 'FIXTURE',
      });
    });

    test('resolve of a protected track fails with "Protected: this track '
        'can\'t be downloaded"', () async {
      final search = json('soundcloud_search');
      final label = (search['collection']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((t) => t['id'] == 255824765);
      serve(onApi: (url) => body(jsonEncode(label)));
      final result = parseSoundcloudTrack(label);

      await expectLater(
        source.resolve(result),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            "Protected: this track can't be downloaded",
          ),
        ),
      );
      expect(http.gets, hasLength(1));
    });

    test('a preview-only track fails with its note', () async {
      final track = json('soundcloud_track')..['policy'] = 'SNIP';
      serve(onApi: (url) => body(jsonEncode(track)));

      await expectLater(
        source.resolve(parseSoundcloudTrack(json('soundcloud_track'))),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            "Preview only: this track can't be downloaded",
          ),
        ),
      );
    });

    test('a stream answer without url is a changed error', () async {
      final track = json('soundcloud_track');
      serve(
        onApi: (url) => url.path.startsWith('/tracks/')
            ? body(jsonEncode(track))
            : body('{}'),
      );
      await expectLater(
        source.resolve(parseSoundcloudTrack(track)),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            'SoundCloud changed something; owntune needs an update',
          ),
        ),
      );
    });
  });

  group('lookup', () {
    final link = SoundcloudLink(
      Uri.parse('https://soundcloud.com/sry4u/the-flip'),
    );

    setUp(() {
      store.id = fixtureId;
    });

    Matcher onlineError(String message) => throwsA(
      isA<OnlineError>().having((e) => e.message, 'message', message),
    );

    test('a resolve answer becomes a result with sourceKey '
        'soundcloud:<id>', () async {
      serve(onApi: (url) => body(text('soundcloud_track.json')));

      final result = await source.lookup(link);

      expect(result.sourceKey, 'soundcloud:$flipId');
      expect(result.source, OnlineSourceId.soundcloud);
      expect(result.availability, OnlineAvailability.available);
    });

    test('the request carries url and client_id', () async {
      serve(onApi: (url) => body(text('soundcloud_track.json')));

      await source.lookup(link);

      final request = http.gets.single;
      expect(request.host, 'api-v2.soundcloud.com');
      expect(request.path, '/resolve');
      expect(request.queryParameters, {
        'url': 'https://soundcloud.com/sry4u/the-flip',
        'client_id': fixtureId,
        'app_locale': 'en',
      });
    });

    test('kind playlist says playlists are not supported', () async {
      final answer = json('soundcloud_track')..['kind'] = 'playlist';
      serve(onApi: (url) => body(jsonEncode(answer)));

      await expectLater(source.lookup(link), onlineError(playlistLinkMessage));
    });

    test('kind user says it is not a song', () async {
      final answer = json('soundcloud_track')..['kind'] = 'user';
      serve(onApi: (url) => body(jsonEncode(answer)));

      await expectLater(source.lookup(link), onlineError(notASongLinkMessage));
    });

    test('a 404 says it is not a song', () async {
      serve(onApi: (url) => body('{}', 404));

      await expectLater(source.lookup(link), onlineError(notASongLinkMessage));
    });

    test('another HTTP error is shown as it is', () async {
      serve(onApi: (url) => body('{}', 500));

      await expectLater(
        source.lookup(link),
        onlineError("SoundCloud didn't answer: HTTP 500"),
      );
    });

    test('a protected track fails with its resolve message', () async {
      // The label track of the search fixture is encrypted.
      final answer = (json('soundcloud_search')['collection']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((t) => t['id'] == 255824765);
      serve(onApi: (url) => body(jsonEncode(answer)));

      await expectLater(
        source.lookup(link),
        onlineError("Protected: this track can't be downloaded"),
      );
    });

    group('short links (on.soundcloud.com)', () {
      final short = SoundcloudLink(
        Uri.parse('https://on.soundcloud.com/AbC12'),
      );

      test('the redirect target is what gets resolved', () async {
        serve(onApi: (url) => body(text('soundcloud_track.json')));
        http.onFinalUrl = (url) async =>
            Uri.parse('https://soundcloud.com/sry4u/the-flip?si=abc&utm=x');

        final result = await source.lookup(short);

        expect(http.finalUrls, [Uri.parse('https://on.soundcloud.com/AbC12')]);
        expect(result.sourceKey, 'soundcloud:$flipId');
        expect(
          http.gets.single.queryParameters['url'],
          'https://soundcloud.com/sry4u/the-flip',
        );
      });

      test('a playlist behind the short link says playlists are not '
          'supported, without calling resolve', () async {
        serve(onApi: (url) => throw StateError('resolve called'));
        store.id = fixtureId;
        http.onFinalUrl = (url) async =>
            Uri.parse('https://soundcloud.com/linkinpark/sets/meteora');

        await expectLater(
          source.lookup(short),
          onlineError(playlistLinkMessage),
        );
      });

      for (final target in [
        'https://soundcloud.com/linkinpark',
        'https://example.com/x',
        'https://on.soundcloud.com/AbC12',
      ]) {
        test('$target is not a song', () async {
          serve(onApi: (url) => throw StateError('resolve called'));
          http.onFinalUrl = (url) async => Uri.parse(target);

          await expectLater(
            source.lookup(short),
            onlineError(notASongLinkMessage),
          );
        });
      }

      test('a normal link is not followed', () async {
        serve(onApi: (url) => body(text('soundcloud_track.json')));

        await source.lookup(link);

        expect(http.finalUrls, isEmpty);
      });
    });

    test('a YouTube link is an ArgumentError', () {
      expect(
        source.lookup(const YoutubeLink('5qZQEq_C3vc')),
        throwsArgumentError,
      );
    });
  });
}
