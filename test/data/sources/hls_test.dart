import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/hls.dart';
import 'package:owntune/data/sources/online_source.dart';

final _base = Uri.parse('https://playback.example.com/a/b/index.m3u8?sig=1');

const _playlist = '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-MAP:URI="https://playback.example.com/aac_160k/init.mp4?sig=a"
#EXTINF:10.007800,
https://playback.example.com/aac_160k/data000.m4s?sig=b
#EXTINF:10.007800,
https://playback.example.com/aac_160k/data001.m4s?sig=c
#EXTINF:8.512000,
https://playback.example.com/aac_160k/data002.m4s?sig=d
#EXT-X-ENDLIST
''';

void expectError(String text, String message) {
  expect(
    () => parseMediaPlaylist(text, _base, service: 'SoundCloud'),
    throwsA(isA<OnlineError>().having((e) => e.message, 'message', message)),
  );
}

const _changed = 'SoundCloud changed something; owntune needs an update';

void main() {
  test('parses init and segments with their durations', () {
    final parsed = parseMediaPlaylist(_playlist, _base, service: 'SoundCloud');
    expect(
      parsed.init,
      Uri.parse('https://playback.example.com/aac_160k/init.mp4?sig=a'),
    );
    expect(parsed.segments, hasLength(3));
    expect(
      parsed.segments[0].url,
      Uri.parse('https://playback.example.com/aac_160k/data000.m4s?sig=b'),
    );
    expect(parsed.segments.map((s) => s.duration), [
      const Duration(microseconds: 10007800),
      const Duration(microseconds: 10007800),
      const Duration(microseconds: 8512000),
    ]);
  });

  test('resolves relative URIs against the playlist URL', () {
    final parsed = parseMediaPlaylist(
      '#EXTM3U\n'
      '#EXT-X-MAP:URI="init.mp4?x=1"\n'
      '#EXTINF:10.0,\n'
      'data000.m4s?x=2\n'
      '#EXTINF:10.0,\n'
      '/other/data001.m4s\n'
      '#EXT-X-ENDLIST\n',
      _base,
      service: 'SoundCloud',
    );
    expect(
      parsed.init,
      Uri.parse('https://playback.example.com/a/b/init.mp4?x=1'),
    );
    expect(
      parsed.segments[0].url,
      Uri.parse('https://playback.example.com/a/b/data000.m4s?x=2'),
    );
    expect(
      parsed.segments[1].url,
      Uri.parse('https://playback.example.com/other/data001.m4s'),
    );
  });

  test('tolerates Windows line endings', () {
    final parsed = parseMediaPlaylist(
      _playlist.replaceAll('\n', '\r\n'),
      _base,
      service: 'SoundCloud',
    );
    expect(parsed.segments, hasLength(3));
  });

  test('#EXT-X-KEY with METHOD=AES-128 fails as protected', () {
    expectError(
      _playlist.replaceFirst(
        '#EXT-X-MAP',
        '#EXT-X-KEY:METHOD=AES-128,URI="https://k.example.com/key"\n#EXT-X-MAP',
      ),
      "Protected: this track can't be downloaded",
    );
  });

  test('#EXT-X-KEY METHOD=NONE is fine', () {
    final parsed = parseMediaPlaylist(
      _playlist.replaceFirst(
        '#EXT-X-MAP',
        '#EXT-X-KEY:METHOD=NONE\n#EXT-X-MAP',
      ),
      _base,
      service: 'SoundCloud',
    );
    expect(parsed.segments, hasLength(3));
  });

  test('#EXT-X-BYTERANGE fails as changed', () {
    expectError(
      _playlist.replaceFirst(
        '#EXTINF:8.512000,\n',
        '#EXTINF:8.512000,\n#EXT-X-BYTERANGE:1000@0\n',
      ),
      _changed,
    );
  });

  test('a second #EXT-X-MAP fails as changed', () {
    expectError(
      _playlist.replaceFirst(
        '#EXTINF:8.512000,',
        '#EXT-X-MAP:URI="https://playback.example.com/other-init.mp4"\n'
            '#EXTINF:8.512000,',
      ),
      _changed,
    );
  });

  test('#EXT-X-DISCONTINUITY fails as changed', () {
    expectError(
      _playlist.replaceFirst(
        '#EXTINF:8.512000,',
        '#EXT-X-DISCONTINUITY\n#EXTINF:8.512000,',
      ),
      _changed,
    );
  });

  test('#EXT-X-DISCONTINUITY-SEQUENCE in the header is fine', () {
    final parsed = parseMediaPlaylist(
      _playlist.replaceFirst(
        '#EXT-X-MAP',
        '#EXT-X-DISCONTINUITY-SEQUENCE:0\n#EXT-X-MAP',
      ),
      _base,
      service: 'SoundCloud',
    );
    expect(parsed.segments, hasLength(3));
  });

  test('a master playlist (#EXT-X-STREAM-INF) fails as changed', () {
    expectError(
      '#EXTM3U\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=160000\n'
      'media.m3u8\n',
      _changed,
    );
  });

  test('no #EXT-X-ENDLIST fails as changed', () {
    expectError(_playlist.replaceFirst('#EXT-X-ENDLIST\n', ''), _changed);
  });

  test('no #EXT-X-MAP fails as changed', () {
    expectError(
      _playlist.replaceFirst(RegExp(r'#EXT-X-MAP:[^\n]*\n'), ''),
      _changed,
    );
  });

  test('no #EXTM3U fails as changed', () {
    expectError(_playlist.replaceFirst('#EXTM3U\n', ''), _changed);
  });

  test('a playlist without segments fails as changed', () {
    expectError(
      '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXT-X-ENDLIST\n',
      _changed,
    );
  });
}
