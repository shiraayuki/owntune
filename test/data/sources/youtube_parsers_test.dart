import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/youtube/youtube_parsers.dart';
import 'package:owntune/edit/track_tags.dart';

Map<String, Object?> fixture(String name) =>
    jsonDecode(File('test/fixtures/online/$name.json').readAsStringSync())
        as Map<String, Object?>;

void main() {
  test('music search: first row is Numb by Linkin Park on Meteora (Bonus Edition), '
      '3:08, 1200px square cover', () {
    final rows = parseMusicSearch(fixture('ytmusic_search'));
    expect(rows, hasLength(20));
    final numb = rows.first;
    expect(numb.id, '5qZQEq_C3vc');
    expect(numb.sourceKey, 'youtube:5qZQEq_C3vc');
    expect(numb.source, OnlineSourceId.ytmusic);
    expect(numb.title, 'Numb');
    expect(numb.subtitle, 'Linkin Park · Meteora (Bonus Edition)');
    expect(numb.duration, const Duration(minutes: 3, seconds: 8));
    expect(numb.tags.title, 'Numb');
    expect(numb.tags.artist, 'Linkin Park');
    expect(numb.tags.album, 'Meteora (Bonus Edition)');
    expect(numb.squareCover, isTrue);
    expect(numb.coverUrl.toString(), endsWith('=w1200-h1200'));
    expect(numb.thumbnail.toString(), contains('=w120-h120'));
    expect(numb.channel, isNull);
  });

  test(
    'video search: 20 rows, first kXYiU_JCYtU, channel Linkin Park, views in '
    'subtitle, 16:9 cover',
    () {
      final rows = parseVideoSearch(fixture('youtube_search'));
      expect(rows, hasLength(20));
      final v = rows.first;
      expect(v.id, 'kXYiU_JCYtU');
      expect(v.sourceKey, 'youtube:kXYiU_JCYtU');
      expect(v.source, OnlineSourceId.youtube);
      expect(v.title, startsWith('Numb'));
      expect(v.channel, 'Linkin Park');
      expect(v.subtitle, 'Linkin Park · 2.8B views');
      expect(v.duration, const Duration(minutes: 3, seconds: 8));
      expect(v.squareCover, isFalse);
      expect(v.coverUrl.toString(), contains('kXYiU_JCYtU'));
      // Videos carry no tags of their own; guessTags fills them later.
      expect(v.tags, const TrackTags());
    },
  );

  test('player ok: itag 140, contentLength > 0, extension m4a', () {
    final s = parsePlayer(fixture('player_ok'));
    expect(s.url.toString(), 'https://example.invalid/videoplayback?itag=140');
    expect(s.contentLength, 3037787);
    expect(s.extension, 'm4a');
    expect(s.bitrate, greaterThan(100000));
  });

  test('player login required: OnlineError mentioning "Sign in"', () {
    expect(
      () => parsePlayer(fixture('player_login_required')),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          allOf(startsWith('YouTube: '), contains('Sign in')),
        ),
      ),
    );
  });

  test('parseVideoDetails on player_ok.json builds a video result', () {
    final r = parseVideoDetails(fixture('player_ok'));
    expect(r.sourceKey, 'youtube:5qZQEq_C3vc');
    expect(r.id, '5qZQEq_C3vc');
    expect(r.source, OnlineSourceId.youtube);
    expect(r.title, 'Numb');
    expect(r.channel, 'Linkin Park - Topic');
    expect(r.subtitle, 'Linkin Park - Topic');
    expect(r.duration, const Duration(seconds: 188));
    expect(r.squareCover, isFalse);
    expect(r.tags, const TrackTags());
    expect(
      r.thumbnail.toString(),
      'https://i.ytimg.com/vi/5qZQEq_C3vc/hq720.jpg',
    );
    expect(r.coverUrl, r.thumbnail);
  });

  test('parseVideoDetails on player_login_required.json throws '
      '"YouTube: ..."', () {
    expect(
      () => parseVideoDetails(fixture('player_login_required')),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          allOf(startsWith('YouTube: '), contains('Sign in')),
        ),
      ),
    );
  });

  test('parseVideoDetails without videoDetails is a changed error', () {
    final player = {...fixture('player_ok')}..remove('videoDetails');
    expect(
      () => parseVideoDetails(player),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          'YouTube changed something; owntune needs an update',
        ),
      ),
    );
  });

  test('player without itag 140 says so', () {
    final json = fixture('player_ok');
    final streaming = json['streamingData']! as Map<String, Object?>;
    streaming['adaptiveFormats'] = (streaming['adaptiveFormats']! as List)
        .where((f) => (f as Map)['itag'] != 140)
        .toList();
    expect(
      () => parsePlayer(json),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          'No M4A audio for this video',
        ),
      ),
    );
  });

  test('search without contents throws "YouTube changed something"', () {
    for (final parse in [parseMusicSearch, parseVideoSearch]) {
      expect(
        () => parse({'responseContext': <String, Object?>{}}),
        throwsA(
          isA<OnlineError>().having(
            (e) => e.message,
            'message',
            "YouTube changed something; owntune needs an update",
          ),
        ),
      );
    }
  });

  test('search with contents but no rows is empty', () {
    expect(parseMusicSearch({'contents': <String, Object?>{}}), isEmpty);
    expect(parseVideoSearch({'contents': <String, Object?>{}}), isEmpty);
  });
}
