import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/player/normalization.dart';

void main() {
  double gain(double? lufs, {bool enabled = true}) =>
      normalizationGain(lufs, enabled: enabled);

  test('a loud song is lowered to the target', () {
    expect(gain(-8), closeTo(0.5012, 1e-3));
  });

  test('a song at or below the target plays unchanged', () {
    expect(gain(-14), 1.0);
    expect(gain(-20), 1.0);
  });

  test('the gain never drops below the floor', () {
    expect(gain(10), kMinGain);
    expect(kMinGain, 0.1);
    expect(kTargetLufs, -14.0);
  });

  test('no or broken loudness plays unchanged', () {
    expect(gain(null), 1.0);
    expect(gain(double.nan), 1.0);
    expect(gain(double.negativeInfinity), 1.0);
  });

  test('switched off plays unchanged', () {
    expect(gain(-8, enabled: false), 1.0);
  });
}
