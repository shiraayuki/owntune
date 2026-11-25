import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/player/cover_colors.dart';

const _white = Color(0xffffffff);

/// A 64×64 RGBA buffer; [pixel] gives the colour of pixel number i.
Uint8List _pixels(List<int> Function(int i) pixel) {
  final out = Uint8List(64 * 64 * 4);
  for (var i = 0; i < 64 * 64; i++) {
    out.setAll(i * 4, pixel(i));
  }
  return out;
}

Uint8List solid(int r, int g, int b, {int a = 255}) =>
    _pixels((_) => [r, g, b, a]);

double hue(Color c) => HSLColor.fromColor(c).hue;

void expectReadable(CoverColors colors) {
  expect(contrastRatio(_white, colors.background), greaterThanOrEqualTo(4.5));
}

void main() {
  test('orange cover', () {
    final colors = coverColorsFromPixels(solid(255, 122, 0), 64, 64)!;
    expect(hue(colors.background), inInclusiveRange(15, 45));
    expectReadable(colors);
  });

  test('near-white and near-black covers keep the contrast', () {
    expectReadable(coverColorsFromPixels(solid(250, 250, 245), 64, 64)!);
    expectReadable(coverColorsFromPixels(solid(5, 5, 8), 64, 64)!);
  });

  test('grey cover gives neutral colours', () {
    final colors = coverColorsFromPixels(solid(128, 128, 128), 64, 64)!;
    expect(HSLColor.fromColor(colors.background).saturation, lessThan(0.1));
    expectReadable(colors);
  });

  test('a vivid colour beats a larger grey area', () {
    final rgba = _pixels(
      (i) => i % 10 < 7 ? [128, 128, 128, 255] : [30, 90, 230, 255],
    );
    final colors = coverColorsFromPixels(rgba, 64, 64)!;
    expect(hue(colors.background), inInclusiveRange(205, 235));
  });

  test('transparent pixels do not count', () {
    final rgba = _pixels((i) => i.isEven ? [255, 0, 0, 0] : [255, 122, 0, 255]);
    expect(
      hue(coverColorsFromPixels(rgba, 64, 64)!.background),
      inInclusiveRange(15, 45),
    );
    expect(coverColorsFromPixels(solid(255, 0, 0, a: 0), 64, 64), isNull);
  });

  test('encoded images', () {
    final image = img.Image(width: 200, height: 200)
      ..clear(img.ColorRgb8(255, 122, 0));
    final colors = coverColorsFromImage(img.encodePng(image));
    expect(colors, isNotNull);
    expect(hue(colors!.background), inInclusiveRange(15, 45));
    expect(coverColorsFromImage(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
