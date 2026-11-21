import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:owntune/edit/cover_image.dart';

Uint8List _jpeg(int width, int height, {int? orientation}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 50, 50));
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(image);
}

/// Left half red, right half blue, as PNG (lossless).
Uint8List _halves(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: width ~/ 2 - 1,
    y2: height - 1,
    color: img.ColorRgb8(255, 0, 0),
  );
  img.fillRect(
    image,
    x1: width ~/ 2,
    y1: 0,
    x2: width - 1,
    y2: height - 1,
    color: img.ColorRgb8(0, 0, 255),
  );
  return img.encodePng(image);
}

void main() {
  group('uprightCover', () {
    test('returns null for garbage', () {
      expect(uprightCover(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('applies EXIF orientation', () {
      final c = uprightCover(_jpeg(40, 20, orientation: 6))!;
      expect((c.width, c.height), (20, 40));
      final decoded = img.decodeJpg(c.bytes)!;
      expect((decoded.width, decoded.height), (20, 40));
    });

    test('downscales to 2000 and never upscales', () {
      final big = uprightCover(_jpeg(4000, 1000))!;
      expect((big.width, big.height), (2000, 500));
      final small = uprightCover(_jpeg(300, 200))!;
      expect((small.width, small.height), (300, 200));
    });
  });

  group('cropCover', () {
    test('returns a square JPEG of at most 1000 px', () {
      final big = cropCover(
        _jpeg(2000, 2000),
        const Rect.fromLTWH(0, 0, 2000, 2000),
      );
      expect(big.sublist(0, 2), [0xff, 0xd8]);
      final decoded = img.decodeJpg(big)!;
      expect((decoded.width, decoded.height), (1000, 1000));

      final small = img.decodeJpg(
        cropCover(_jpeg(500, 500), const Rect.fromLTWH(50, 50, 400, 400)),
      )!;
      expect((small.width, small.height), (400, 400));
    });

    test('a tiny rect still gives a 1 px cover', () {
      final out = img.decodeJpg(
        cropCover(_jpeg(10, 10), const Rect.fromLTWH(0, 0, 0.3, 0.3)),
      )!;
      expect((out.width, out.height), (1, 1));
    });

    test('takes the requested area', () {
      final out = img.decodeJpg(
        cropCover(_halves(200, 100), const Rect.fromLTWH(100, 0, 100, 100)),
      )!;
      final centre = out.getPixel(50, 50);
      expect(centre.b, greaterThan(200));
      expect(centre.r, lessThan(60));
    });
  });

  group('crop math', () {
    test('initial transform centres the image', () {
      const image = Size(2000, 1000);
      expect(
        cropRectFor(initialCropTransform(image, 300), image, 300),
        const Rect.fromLTWH(500, 0, 1000, 1000),
      );
    });

    test('panorama starts covering the frame', () {
      const image = Size(4000, 500);
      expect(
        cropRectFor(initialCropTransform(image, 300), image, 300),
        const Rect.fromLTWH(1750, 0, 500, 500),
      );
    });

    test('zoomed and moved transform maps back', () {
      const image = Size(2000, 1000);
      final zoomed = Matrix4.diagonal3Values(2, 2, 1)
        ..multiply(initialCropTransform(image, 300));
      expect(
        cropRectFor(zoomed, image, 300),
        const Rect.fromLTWH(500, 0, 500, 500),
      );
    });

    test('rect is clamped into the image', () {
      const image = Size(2000, 1000);
      final moved = Matrix4.translationValues(-400, 0, 0);
      final rect = cropRectFor(moved, image, 300);
      expect(rect.right, lessThanOrEqualTo(2000));
      expect(rect.width, 1000);
      expect(rect.height, 1000);
    });
  });
}
