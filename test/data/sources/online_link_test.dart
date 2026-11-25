import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/online_link.dart';

void _youtube(String text, [String id = '5qZQEq_C3vc']) {
  final link = parseOnlineLink(text);
  expect(link, isA<YoutubeLink>(), reason: text);
  expect((link! as YoutubeLink).videoId, id, reason: text);
}

void _soundcloud(String text, String expected) {
  final link = parseOnlineLink(text);
  expect(link, isA<SoundcloudLink>(), reason: text);
  expect((link! as SoundcloudLink).url, Uri.parse(expected), reason: text);
}

void _unsupported(String text, String message) {
  final link = parseOnlineLink(text);
  expect(link, isA<UnsupportedLink>(), reason: text);
  expect((link! as UnsupportedLink).message, message, reason: text);
}

void main() {
  group('YouTube', () {
    test('watch link', () {
      _youtube('https://www.youtube.com/watch?v=5qZQEq_C3vc');
    });
    test('YouTube Music link with tracking parameter', () {
      _youtube('https://music.youtube.com/watch?v=5qZQEq_C3vc&si=x');
    });
    test('mobile host', () {
      _youtube('https://m.youtube.com/watch?v=5qZQEq_C3vc');
    });
    test('short link with si and timestamp', () {
      _youtube('https://youtu.be/5qZQEq_C3vc?si=abc&t=42');
    });
    test('shorts link without scheme', () {
      _youtube('youtube.com/shorts/5qZQEq_C3vc');
    });
    test('live link', () {
      _youtube('https://www.youtube.com/live/5qZQEq_C3vc');
    });
    test('embed link', () {
      _youtube('https://www.youtube.com/embed/5qZQEq_C3vc');
    });
    test('watch link with a mix list opens the video', () {
      _youtube('https://www.youtube.com/watch?v=5qZQEq_C3vc&list=RDabc');
    });
    test('the playlist page is a playlist', () {
      _unsupported(
        'https://www.youtube.com/playlist?list=PL123',
        playlistLinkMessage,
      );
    });
    test('a watch link with only a list is a playlist', () {
      _unsupported(
        'https://music.youtube.com/watch?list=OLAK5',
        playlistLinkMessage,
      );
    });
    test('a channel is not a song', () {
      _unsupported('https://www.youtube.com/@linkinpark', notASongLinkMessage);
    });
    test('a bad video id is not a song', () {
      _unsupported('https://youtube.com/watch?v=short', notASongLinkMessage);
    });
    test('another site is not a song', () {
      _unsupported('https://example.com/song', notASongLinkMessage);
    });
  });

  group('SoundCloud', () {
    test('track link loses query parameters', () {
      _soundcloud(
        'https://soundcloud.com/sry4u/linkin-park-numb-sry4u-flip-1'
            '?si=x&utm_source=clipboard',
        'https://soundcloud.com/sry4u/linkin-park-numb-sry4u-flip-1',
      );
    });
    test('mobile host is kept', () {
      _soundcloud(
        'https://m.soundcloud.com/sry4u/numb',
        'https://m.soundcloud.com/sry4u/numb',
      );
    });
    test('share link on.soundcloud.com', () {
      _soundcloud(
        'https://on.soundcloud.com/AbC123',
        'https://on.soundcloud.com/AbC123',
      );
    });
    test('a set is a playlist', () {
      _unsupported(
        'https://soundcloud.com/linkinpark/sets/meteora',
        playlistLinkMessage,
      );
    });
    test('a user page is not a song', () {
      _unsupported('https://soundcloud.com/linkinpark', notASongLinkMessage);
    });
    test('a site page is not a song', () {
      _unsupported('https://soundcloud.com/discover', notASongLinkMessage);
    });
  });

  group('malformed links', () {
    for (final text in [
      'https://www.youtube.com/watch?v=%FF%FE',
      'https://youtu.be/%FF%FE',
      'https://soundcloud.com/%FF/%FE',
    ]) {
      test('$text is not a song (and does not throw)', () {
        _unsupported(text, notASongLinkMessage);
      });
    }
  });

  group('text and clipboard', () {
    test('surrounding whitespace and newline are ignored', () {
      _youtube('  https://youtu.be/5qZQEq_C3vc\n');
    });
    for (final text in [
      'AC/DC',
      'Mr. Brightside',
      'youtube rewind',
      'linkin park numb',
      '',
    ]) {
      test('"$text" is a normal search', () {
        expect(parseOnlineLink(text), isNull);
      });
    }
  });
}
