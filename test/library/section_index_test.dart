import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/library/section_index.dart';

void main() {
  test('indexLetters is A–Z then #', () {
    expect(indexLetters, hasLength(27));
    expect(indexLetters.first, 'A');
    expect(indexLetters[25], 'Z');
    expect(indexLetters.last, '#');
  });

  test('collapseIndex keeps everything when there is room', () {
    expect(collapseIndex(27), indexLetters);
    expect(collapseIndex(40), indexLetters);
  });

  test('collapseIndex fits a small strip with bullets', () {
    for (final slots in [3, 5, 12, 20, 26]) {
      final entries = collapseIndex(slots);
      expect(entries.length, lessThanOrEqualTo(slots), reason: '$slots');
      expect(entries.first, 'A');
      expect(entries.last, '#');
      expect(entries, contains('•'));
    }
  });

  test('bulletTarget is the first hidden letter after the previous entry', () {
    final entries = collapseIndex(5); // A • ? • #
    final i = entries.indexOf('•');
    expect(bulletTarget(entries, i), 'B');
  });

  test('jumpTarget', () {
    expect(jumpTarget('C', {'A', 'D'}), 'D');
    expect(jumpTarget('D', {'A', 'D'}), 'D');
    expect(jumpTarget('Z', {'A'}), isNull);
    expect(jumpTarget('#', {'#'}), '#');
    expect(jumpTarget('Y', {'#'}), '#');
  });
}
