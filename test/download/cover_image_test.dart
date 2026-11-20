import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:owntune/download/cover_image.dart';

Uint8List jpeg(int w, int h) => img.encodeJpg(img.Image(width: w, height: h));

void main() {
  test('a 1280x720 frame becomes a 720x720 JPEG', () {
    final cover = prepareCover(jpeg(1280, 720), cropToSquare: true)!;
    expect(cover.mime, 'image/jpeg');
    final out = img.decodeJpg(cover.data)!;
    expect((out.width, out.height), (720, 720));
  });

  test('a letterboxed 480x360 frame becomes 270x270', () {
    final cover = prepareCover(jpeg(480, 360), cropToSquare: true)!;
    final out = img.decodeJpg(cover.data)!;
    expect((out.width, out.height), (270, 270));
  });

  test('a PNG kept as is when no crop is asked for', () {
    final png = img.encodePng(img.Image(width: 64, height: 64));
    final cover = prepareCover(png, cropToSquare: false)!;
    expect(cover.mime, 'image/png');
    expect(cover.data, png);
  });

  test('a JPEG kept as is when no crop is asked for', () {
    final bytes = jpeg(64, 64);
    final cover = prepareCover(bytes, cropToSquare: false)!;
    expect(cover.mime, 'image/jpeg');
    expect(cover.data, bytes);
  });

  test('another format is re-encoded as JPEG', () {
    final bmp = img.encodeBmp(img.Image(width: 64, height: 64));
    final cover = prepareCover(bmp, cropToSquare: false)!;
    expect(cover.mime, 'image/jpeg');
    expect(img.decodeJpg(cover.data)!.width, 64);
  });

  test('garbage bytes give no cover', () {
    expect(
      prepareCover(Uint8List.fromList([1, 2, 3, 4]), cropToSquare: true),
      isNull,
    );
  });
}
