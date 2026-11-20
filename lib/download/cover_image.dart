import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A cover image ready to be written into a file.
typedef CoverBytes = ({Uint8List data, String mime});

/// Turns downloaded image bytes into a JPEG or PNG cover; null when the
/// bytes are not a readable image.
///
/// With [cropToSquare] (16:9 video thumbnails), the centered 16:9 picture
/// area is cut to its centered square; thumbnails with black bars (4:3) lose
/// the bars that way. Without it, JPEG and PNG are kept byte for byte, and
/// other formats are re-encoded as JPEG.
///
/// Synchronous and CPU-bound: call it through `Isolate.run`.
CoverBytes? prepareCover(Uint8List bytes, {required bool cropToSquare}) {
  if (!cropToSquare) {
    final mime = _mimeOf(bytes);
    if (mime != null) return (data: bytes, mime: mime);
  }
  final img.Image? image;
  try {
    image = img.decodeImage(bytes);
  } on Object {
    return null;
  }
  if (image == null) return null;
  final out = cropToSquare ? _squareOfPicture(image) : image;
  return (data: img.encodeJpg(out, quality: 90), mime: 'image/jpeg');
}

img.Image _squareOfPicture(img.Image image) {
  // Height of the 16:9 picture inside the image (the whole image when it is
  // 16:9 or wider).
  final pictureHeight = image.width * 9 / 16 < image.height
      ? (image.width * 9 / 16).round()
      : image.height;
  final side = pictureHeight;
  return img.copyCrop(
    image,
    x: (image.width - side) ~/ 2,
    y: (image.height - side) ~/ 2,
    width: side,
    height: side,
  );
}

String? _mimeOf(Uint8List b) {
  if (b.length > 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) {
    return 'image/jpeg';
  }
  if (b.length > 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4e &&
      b[3] == 0x47) {
    return 'image/png';
  }
  return null;
}
