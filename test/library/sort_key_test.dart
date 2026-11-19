import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/library/sort_key.dart';

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

  group('foldKey', () {
    test('keeps the article', () {
      expect(foldKey(' The Quiet '), 'the quiet');
      expect(foldKey('KÖLN'), 'koln');
    });
  });

  group('compareKeys', () {
    test('puts # entries after letters', () {
      final keys = ['99 luftballons', 'zebra', '', 'apple']..sort(compareKeys);
      expect(keys, ['apple', 'zebra', '', '99 luftballons']);
      expect(compareKeys(sortKey('99 Luftballons'), sortKey('Zebra')), 1);
    });
  });
}
