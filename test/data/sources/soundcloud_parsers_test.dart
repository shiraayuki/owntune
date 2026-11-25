import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_parsers.dart';

Map<String, Object?> fixture(String name) =>
    jsonDecode(File('test/fixtures/online/$name.json').readAsStringSync())
        as Map<String, Object?>;

/// The tracks of the recorded "linkin park numb" search.
List<Map<String, Object?>> searchTracks() => [
  for (final t in fixture('soundcloud_search')['collection']! as List)
    t as Map<String, Object?>,
];

Map<String, Object?> trackWithId(int id) =>
    searchTracks().firstWhere((t) => t['id'] == id);

/// A free track from the fixtures, changed by [change].
Map<String, Object?> freeTrack([
  void Function(Map<String, Object?> track)? change,
]) {
  final track = jsonDecode(
    jsonEncode(fixture('soundcloud_track')),
  ) as Map<String, Object?>;
  change?.call(track);
  return track;
}

List<Map<String, Object?>> transcodingsOf(Map<String, Object?> track) => [
  for (final t
      in ((track['media']! as Map<String, Object?>)['transcodings']! as List))
    t as Map<String, Object?>,
];

/// Only [keep] transcodings stay.
void keepTranscodings(
  Map<String, Object?> track,
  bool Function(Map<String, Object?> t) keep,
) {
  (track['media']! as Map<String, Object?>)['transcodings'] = [
    ...transcodingsOf(track).where(keep),
  ];
}

const flipId = 2443730886;
const labelId = 255824765;

void main() {
  test('search keeps 20 tracks with sourceKey soundcloud:<id>', () {
    final rows = parseSoundcloudSearch(fixture('soundcloud_search'));
    expect(rows, hasLength(20));
    expect(rows.first.sourceKey, 'soundcloud:$labelId');
    expect(rows.first.id, '$labelId');
    expect(rows.every((r) => r.source == OnlineSourceId.soundcloud), isTrue);
    expect(rows.every((r) => r.sourceKey == 'soundcloud:${r.id}'), isTrue);
  });

  test('search without collection is a changed error', () {
    expect(
      () => parseSoundcloudSearch({'total_results': 0}),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          'SoundCloud changed something; owntune needs an update',
        ),
      ),
    );
  });

  test('search keeps only items of kind track', () {
    final json = fixture('soundcloud_search');
    final items = json['collection']! as List;
    final rows = parseSoundcloudSearch({
      'collection': [
        {'kind': 'playlist', 'id': 1, 'title': 'A set'},
        ...items.take(2),
      ],
    });
    expect(rows, hasLength(2));
  });

  test('the LINKIN PARK upload is protected', () {
    final row = parseSoundcloudTrack(trackWithId(labelId));
    expect(row.availability, OnlineAvailability.protected);
    expect(row.availability.note, 'Protected');
    expect(row.kbps, isNull);
  });

  test('"Linkin Park - Numb (SRY4U FLIP)" is available at 160 kbps', () {
    final row = parseSoundcloudTrack(trackWithId(flipId));
    expect(row.title, 'Linkin Park - Numb (SRY4U FLIP)');
    expect(row.availability, OnlineAvailability.available);
    expect(row.availability.note, isNull);
    expect(row.kbps, 160);
    expect(row.duration, const Duration(milliseconds: 188848));
    expect(row.squareCover, isTrue);
    expect(row.channel, isNull);
  });

  test('a track with only aac_96k picks 96', () {
    final track = freeTrack(
      (t) => keepTranscodings(t, (x) => x['preset'] != 'aac_160k'),
    );
    expect(pickTranscoding(track)!.kbps, 96);
    expect(parseSoundcloudTrack(track).kbps, 96);
    expect(pickTranscoding(track)!.url.toString(), endsWith('/stream/hls'));
  });

  test('160 is picked before 96', () {
    final picked = pickTranscoding(freeTrack())!;
    expect(picked.kbps, 160);
    final aac160 = transcodingsOf(freeTrack())
        .firstWhere((t) => t['preset'] == 'aac_160k');
    expect(picked.url.toString(), aac160['url']);
  });

  test('policy SNIP is preview only', () {
    final track = freeTrack((t) => t['policy'] = 'SNIP');
    expect(availabilityOf(track), OnlineAvailability.previewOnly);
    expect(availabilityOf(track).note, 'Preview only');
    expect(parseSoundcloudTrack(track).kbps, isNull);
  });

  test('all usable transcodings snipped is preview only', () {
    final track = freeTrack((t) {
      for (final x in transcodingsOf(t)) {
        x['snipped'] = true;
      }
    });
    expect(pickTranscoding(track), isNull);
    expect(availabilityOf(track), OnlineAvailability.previewOnly);
  });

  test('policy BLOCK is not available', () {
    final track = freeTrack((t) => t['policy'] = 'BLOCK');
    expect(availabilityOf(track), OnlineAvailability.unavailable);
    expect(availabilityOf(track).note, 'Not available');
  });

  test('opus/mp3-only is not available', () {
    final track = freeTrack((t) {
      keepTranscodings(t, (x) => x['preset'] == 'abr_sq');
      for (final x in transcodingsOf(t)) {
        x['preset'] = 'opus_0_0';
        (x['format']! as Map<String, Object?>)['mime_type'] =
            'audio/ogg; codecs="opus"';
      }
    });
    expect(pickTranscoding(track), isNull);
    expect(availabilityOf(track), OnlineAvailability.unavailable);
  });

  test('a track without transcodings is not available', () {
    final track = freeTrack((t) => t.remove('media'));
    expect(availabilityOf(track), OnlineAvailability.unavailable);
  });

  group('artwork', () {
    test('-large becomes -t300x300 / -t500x500', () {
      final track = freeTrack();
      final artwork = track['artwork_url']! as String;
      expect(artwork, endsWith('-large.jpg'));
      expect(
        soundcloudArtwork(track, 't300x300').toString(),
        artwork.replaceFirst('-large', '-t300x300'),
      );
      expect(
        soundcloudArtwork(track, 't500x500').toString(),
        artwork.replaceFirst('-large', '-t500x500'),
      );
      final row = parseSoundcloudTrack(track);
      expect(row.thumbnail.toString(), contains('-t300x300.jpg'));
      expect(row.coverUrl.toString(), contains('-t500x500.jpg'));
    });

    test('falls back to the avatar', () {
      final track = freeTrack((t) => t['artwork_url'] = null);
      final avatar =
          (track['user']! as Map<String, Object?>)['avatar_url']! as String;
      expect(
        soundcloudArtwork(track, 't300x300').toString(),
        avatar.replaceFirst('-large', '-t300x300'),
      );
      expect(
        parseSoundcloudTrack(track).coverUrl.toString(),
        avatar.replaceFirst('-large', '-t500x500'),
      );
    });

    test(
      'no artwork and no avatar keeps the row: empty thumbnail, no cover',
      () {
        final track = freeTrack((t) {
          t['artwork_url'] = null;
          (t['user']! as Map<String, Object?>)['avatar_url'] = null;
        });
        expect(soundcloudArtwork(track, 't300x300'), isNull);
        final row = parseSoundcloudTrack(track);
        expect(row.thumbnail, Uri());
        expect(row.coverUrl, isNull);
        expect(row.availability, OnlineAvailability.available);
      },
    );
  });

  test('subtitle is "SRY4U · 454 plays"', () {
    final row = parseSoundcloudTrack(trackWithId(flipId));
    expect(row.subtitle, 'SRY4U · 454 plays');
  });

  test('subtitle uses the compact count', () {
    final track = freeTrack((t) => t['playback_count'] = 48000);
    expect(parseSoundcloudTrack(track).subtitle, 'SRY4U · 48K plays');
  });

  test('subtitle without a play count is the uploader', () {
    final track = freeTrack((t) => t.remove('playback_count'));
    expect(parseSoundcloudTrack(track).subtitle, 'SRY4U');
  });

  test('compactCount', () {
    expect(compactCount(0), '0');
    expect(compactCount(950), '950');
    expect(compactCount(1000), '1K');
    expect(compactCount(6249), '6.2K');
    expect(compactCount(48000), '48K');
    expect(compactCount(210000), '210K');
    expect(compactCount(2139644), '2.1M');
    expect(compactCount(29662914), '29M');
  });

  group('tags', () {
    test('"Linkin Park - Numb (SRY4U FLIP)" splits into Linkin Park / '
        'Numb (SRY4U FLIP)', () {
      final tags = soundcloudTags(trackWithId(flipId));
      expect(tags.artist, 'Linkin Park');
      expect(tags.title, 'Numb (SRY4U FLIP)');
    });

    test('no separator: artist from publisher_metadata.artist, else '
        'username', () {
      final withMeta = soundcloudTags(
        freeTrack((t) {
          t['title'] = 'Numb';
          t['publisher_metadata'] = {'artist': 'LINKIN PARK, SRY4U'};
        }),
      );
      expect(withMeta.title, 'Numb');
      expect(withMeta.artist, 'LINKIN PARK, SRY4U');

      final without = soundcloudTags(
        freeTrack((t) {
          t['title'] = 'Numb';
          t['publisher_metadata'] = null;
        }),
      );
      expect(without.artist, 'SRY4U');
    });

    test('a username like "Official Foo" is not cleaned', () {
      final tags = soundcloudTags(
        freeTrack((t) {
          t['title'] = 'Numb';
          t['publisher_metadata'] = null;
          (t['user']! as Map<String, Object?>)['username'] = 'Official Foo';
        }),
      );
      expect(tags.artist, 'Official Foo');
    });

    test('album from album_title, else release_title', () {
      final both = soundcloudTags(
        freeTrack(
          (t) => t['publisher_metadata'] = {
            'album_title': 'Meteora',
            'release_title': 'Numb',
          },
        ),
      );
      expect(both.album, 'Meteora');
      final release = soundcloudTags(
        freeTrack((t) => t['publisher_metadata'] = {'release_title': 'Numb'}),
      );
      expect(release.album, 'Numb');
      expect(soundcloudTags(freeTrack()).album, isNull);
    });

    test('genre and year are carried', () {
      final tags = soundcloudTags(
        freeTrack((t) {
          t['genre'] = 'Dubstep';
          t['release_date'] = '2024-05-01T00:00:00Z';
        }),
      );
      expect(tags.genre, 'Dubstep');
      expect(tags.year, 2024);
      final none = soundcloudTags(
        freeTrack((t) {
          t['genre'] = '';
          t['release_date'] = null;
        }),
      );
      expect(none.genre, isNull);
      expect(none.year, isNull);
    });

    test('"NHẠC NGHE ĐI TẮM 🎧" keeps its title, artist = username', () {
      final row = parseSoundcloudTrack(
        freeTrack((t) {
          t['title'] = 'NHẠC NGHE ĐI TẮM 🎧';
          t['publisher_metadata'] = null;
          (t['user']! as Map<String, Object?>)['username'] = 'Mai Linh';
        }),
      );
      expect(row.tags.title, 'NHẠC NGHE ĐI TẮM 🎧');
      expect(row.tags.artist, 'Mai Linh');
      expect(row.title, 'NHẠC NGHE ĐI TẮM 🎧');
      expect(row.subtitle, startsWith('Mai Linh'));
    });

    test('a title that is only a noise bracket keeps the raw title', () {
      final tags = soundcloudTags(
        freeTrack((t) => t['title'] = '(Free Download)'),
      );
      expect(tags.title, '(Free Download)');
    });
  });
}
