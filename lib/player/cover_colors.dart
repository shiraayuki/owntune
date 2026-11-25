import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

/// The colour Now Playing takes from a cover (dark mode): a flat
/// [background] on which white text and white controls stay readable.
@immutable
class CoverColors {
  const CoverColors({required this.background});

  final Color background;

  @override
  bool operator ==(Object other) =>
      other is CoverColors && other.background == background;

  @override
  int get hashCode => background.hashCode;

  @override
  String toString() => 'CoverColors($background)';
}

const _white = Color(0xffffffff);

/// Minimum contrast (WCAG AA for normal text).
const _minContrast = 4.5;

/// Decodes [encoded] (JPEG, PNG, WebP, …), scales it to 64×64 and picks its
/// colours; null when the bytes are no image. Synchronous and CPU-bound:
/// call it through `Isolate.run`.
CoverColors? coverColorsFromImage(Uint8List encoded) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(encoded);
  } on Object {
    return null;
  }
  if (decoded == null) return null;
  final small = img.copyResize(
    decoded,
    width: 64,
    height: 64,
    interpolation: img.Interpolation.average,
  );
  final rgba = small
      .convert(format: img.Format.uint8, numChannels: 4, alpha: 255)
      .getBytes(order: img.ChannelOrder.rgba);
  return coverColorsFromPixels(rgba, small.width, small.height);
}

/// Picks the colours of a cover from its RGBA pixels: the dominant colour
/// that is vivid enough (a vivid colour beats a larger grey area), else the
/// most frequent one. Pixels with alpha below 128 do not count; null when
/// none is left.
CoverColors? coverColorsFromPixels(Uint8List rgba, int width, int height) {
  // Buckets of 4 bits per channel, each with the sums of its pixels.
  final counts = <int, int>{};
  final sums = <int, List<int>>{};
  var opaque = 0;
  final n = math.min(width * height, rgba.length ~/ 4);
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    if (rgba[o + 3] < 128) continue;
    final r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
    final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
    counts[key] = (counts[key] ?? 0) + 1;
    final s = sums.putIfAbsent(key, () => [0, 0, 0]);
    s[0] += r;
    s[1] += g;
    s[2] += b;
    opaque++;
  }
  if (opaque == 0) return null;

  HSLColor mean(int key) {
    final s = sums[key]!, c = counts[key]!;
    return HSLColor.fromColor(
      Color.fromARGB(
        255,
        (s[0] / c).round(),
        (s[1] / c).round(),
        (s[2] / c).round(),
      ),
    );
  }

  int? vivid;
  var vividScore = -1.0;
  int? common;
  var commonCount = -1;
  for (final key in counts.keys) {
    final count = counts[key]!;
    if (count > commonCount) {
      common = key;
      commonCount = count;
    }
    final hsl = mean(key);
    final isVivid =
        hsl.saturation >= 0.25 &&
        hsl.lightness >= 0.12 &&
        hsl.lightness <= 0.88;
    if (!isVivid) continue;
    final score = count * (0.5 + hsl.saturation);
    if (score > vividScore) {
      vivid = key;
      vividScore = score;
    }
  }
  final pick = vivid != null && counts[vivid]! >= opaque * 0.05
      ? vivid
      : common!;
  final base = mean(pick);

  var background = base.withLightness(math.min(base.lightness, 0.35));
  while (contrastRatio(_white, background.toColor()) < _minContrast &&
      background.lightness > 0) {
    background = background.withLightness(
      math.max(0, background.lightness - 0.02),
    );
  }

  return CoverColors(background: background.toColor());
}

/// The WCAG 2 contrast ratio of two opaque colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
