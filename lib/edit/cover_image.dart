import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

/// A picked image turned upright, as JPEG, with its pixel size.
typedef UprightCover = ({Uint8List bytes, int width, int height});

/// Longest side of the image the crop page works on.
const _maxSourceSide = 2000;

/// Longest side of a finished cover.
const _maxCoverSide = 1000;

/// Decodes [source] (null when the `image` package cannot read it, e.g.
/// HEIC), applies its EXIF orientation and downscales it so the longer side
/// is at most 2000 px. The crop page shows these bytes and [cropCover] cuts
/// them, so both see the same upright pixels.
///
/// Synchronous and CPU-bound: call it through `Isolate.run`.
UprightCover? uprightCover(Uint8List source) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } on Object {
    return null;
  }
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final longer = math.max(image.width, image.height);
  if (longer > _maxSourceSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: _maxSourceSide)
        : img.copyResize(image, height: _maxSourceSide);
  }
  return (
    bytes: img.encodeJpg(image, quality: 95),
    width: image.width,
    height: image.height,
  );
}

/// Cuts [rect] (image pixels) out of [upright] and returns it as a JPEG
/// cover (quality 90) of at most 1000 px per side, never upscaled.
///
/// Synchronous and CPU-bound: call it through `Isolate.run`.
Uint8List cropCover(Uint8List upright, Rect rect) {
  final image = img.decodeImage(upright)!;
  final x = rect.left.round().clamp(0, image.width - 1);
  final y = rect.top.round().clamp(0, image.height - 1);
  // At least 1 px, so a deep zoom into a tiny image never crops to nothing.
  final side = math.max(
    1,
    math.min(rect.width.round(), math.min(image.width - x, image.height - y)),
  );
  var out = img.copyCrop(image, x: x, y: y, width: side, height: side);
  if (side > _maxCoverSide) {
    out = img.copyResize(out, width: _maxCoverSide, height: _maxCoverSide);
  }
  return img.encodeJpg(out, quality: 90);
}

/// Scale at which an [image] just covers a [frame]-sized square: the crop
/// page lays the image out at `image * baseScale`.
double cropBaseScale(Size image, double frame) => frame / image.shortestSide;

/// The transform that centres the laid-out image in the [frame]×[frame]
/// viewport, at zoom 1.
Matrix4 initialCropTransform(Size image, double frame) {
  final child = image * cropBaseScale(image, frame);
  return Matrix4.translationValues(
    -(child.width - frame) / 2,
    -(child.height - frame) / 2,
    0,
  );
}

/// The square of the image (in image pixels) that the viewport shows under
/// [transform]: the viewport mapped back through the transform, divided by
/// the base scale, clamped into the image and kept square.
Rect cropRectFor(Matrix4 transform, Size image, double frame) {
  final inverse = Matrix4.inverted(transform);
  final base = cropBaseScale(image, frame);
  final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero) / base;
  final bottomRight =
      MatrixUtils.transformPoint(inverse, Offset(frame, frame)) / base;
  final side = math.min(bottomRight.dx - topLeft.dx, image.shortestSide);
  final left = topLeft.dx.clamp(0.0, image.width - side);
  final top = topLeft.dy.clamp(0.0, image.height - side);
  return Rect.fromLTWH(left, top, side, side);
}
