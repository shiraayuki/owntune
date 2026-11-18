import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/sort_key.dart';

Track _track(int id, {String? title, String? artist, String name = 'f.mp3'}) {
  return Track(
    id: id,
    fileName: '$id.mp3',
    originalName: name,
    contentHash: 'hash$id',
    title: title,
    artist: artist,
    durationMs: 1000,
    addedAt: DateTime(2026),
    playCount: 0,
  );
}

void main() {
  group('sortKey', () {
    test('removes leading "the " and lowercases', () {
      expect(sortKey('The Quiet Coast'), 'quiet coast');
    });
    test('trims and folds diacritics', () {
      expect(sortKey('  Ärger '), 'arger');
      expect(sortKey('Straße'), 'strasse');
      expect(sortKey('Çañón éèê öòóô üùúû àáâ'), 'canon eee oooo uuuu aaa');
    });
  });

  group('sectionLetter', () {
    test('letters, digits and the article', () {
      expect(sectionLetter('Ärger'), 'A');
      expect(sectionLetter('99 Luftballons'), '#');
      expect(sectionLetter('the beatles'), 'B');
      expect(sectionLetter(''), '#');
    });
  });

  group('display fallbacks', () {
    test('displayTitle', () {
      expect(displayTitle(null, 'demo_3.wav'), 'demo_3');
      expect(displayTitle('  ', 'x.mp3'), 'x');
      expect(displayTitle('Real', 'x.mp3'), 'Real');
    });
    test('displayArtist', () {
      expect(displayArtist(null), 'Unknown Artist');
      expect(displayArtist(' '), 'Unknown Artist');
      expect(displayArtist('Someone'), 'Someone');
    });
  });

  group('sortByTitle', () {
    test('orders by title key without mutating input', () {
      final input = [
        _track(1, title: 'b'),
        _track(2, title: 'The a'),
        _track(3, title: 'Ä c'),
      ];
      final sorted = sortByTitle(input);
      expect(sorted.map((t) => t.title), ['The a', 'Ä c', 'b']);
      expect(input.map((t) => t.title), ['b', 'The a', 'Ä c']);
    });
    test('ties are broken by artist', () {
      final sorted = sortByTitle([
        _track(1, title: 'Same', artist: 'Zed'),
        _track(2, title: 'Same', artist: 'The Abe'),
      ]);
      expect(sorted.map((t) => t.id), [2, 1]);
    });
  });
}
