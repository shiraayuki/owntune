import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/download/guess_tags.dart';

void main() {
  // videoTitle, channel, expected artist, expected title
  const cases = [
    (
      'Linkin Park - Numb (Official Music Video) [4K UPGRADE]',
      'Linkin Park',
      'Linkin Park',
      'Numb',
    ),
    (
      'Numb (Official Music Video) [4K UPGRADE] – Linkin Park',
      'Linkin Park',
      'Linkin Park',
      'Numb',
    ),
    (
      'Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)',
      'Rick Astley',
      'Rick Astley',
      'Never Gonna Give You Up',
    ),
    (
      'Rammstein - Deutschland (Official Video)',
      'Rammstein Official',
      'Rammstein',
      'Deutschland',
    ),
    (
      'Juno Vale – After the Rain (Live at Paper Hall)',
      'Paper Hall Sessions',
      'Juno Vale',
      'After the Rain (Live at Paper Hall)',
    ),
    (
      'After the Rain (Lyrics)',
      'Juno Vale - Topic',
      'Juno Vale',
      'After the Rain',
    ),
    (
      'Get Lucky (Daft Punk Remix)',
      'DaftPunkVEVO',
      'DaftPunk',
      'Get Lucky (Daft Punk Remix)',
    ),
  ];

  for (final (videoTitle, channel, artist, title) in cases) {
    test('guessTags("$videoTitle", "$channel")', () {
      final tags = guessTags(videoTitle: videoTitle, channel: channel);
      expect(tags.artist, artist);
      expect(tags.title, title);
      expect(tags.album, isNull);
    });
  }

  for (final raw in [
    'Numb (FREE DL)',
    'Numb [FREE DOWNLOAD]',
    'Numb (Free Download)',
  ]) {
    test('"$raw" loses the bracket', () {
      final tags = guessTags(videoTitle: raw, channel: 'SRY4U');
      expect(tags.title, 'Numb');
    });
  }

  test('"(Free Mix)" is kept', () {
    final tags = guessTags(videoTitle: 'Numb (Free Mix)', channel: 'SRY4U');
    expect(tags.title, 'Numb (Free Mix)');
  });
}
