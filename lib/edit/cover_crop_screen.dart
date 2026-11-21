import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/edit/cover_image.dart';

/// Opens the square crop page for [cover] above everything; returns the
/// chosen square in image pixels, or null when cancelled.
Future<Rect?> openCoverCrop(BuildContext context, UprightCover cover) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<Rect>(
        fullscreenDialog: true,
        builder: (_) => CoverCropScreen(cover: cover),
      ),
    );

/// Move and Scale: the picked image under a square frame; pinch zooms, drag
/// moves, and the image always covers the frame.
class CoverCropScreen extends StatefulWidget {
  const CoverCropScreen({super.key, required this.cover});

  final UprightCover cover;

  @override
  State<CoverCropScreen> createState() => _CoverCropScreenState();
}

class _CoverCropScreenState extends State<CoverCropScreen> {
  final _transform = TransformationController();
  double? _frame;

  Size get _image =>
      Size(widget.cover.width.toDouble(), widget.cover.height.toDouble());

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _choose() {
    final frame = _frame;
    if (frame == null) return;
    Navigator.of(context).pop(cropRectFor(_transform.value, _image, frame));
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    const white = Colors.white;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  TextButton(
                    key: const Key('crop-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: white),
                    child: const Text('Cancel', style: TextStyle(fontSize: 17)),
                  ),
                  const Expanded(
                    child: Text(
                      'Move and Scale',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: white,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('crop-choose'),
                    onPressed: _choose,
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    child: const Text(
                      'Choose',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final frame = math.max(
                  1.0,
                  math.min(box.maxWidth - 32, box.maxHeight - 32),
                );
                if (frame != _frame) {
                  final first = _frame == null;
                  _frame = frame;
                  final start = initialCropTransform(_image, frame);
                  // Later size changes (rotation) must not notify the
                  // viewer while it builds.
                  if (first) {
                    _transform.value = start;
                  } else {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _transform.value = start,
                    );
                  }
                }
                final child = _image * cropBaseScale(_image, frame);
                final hole = Rect.fromCenter(
                  center: box.biggest.center(Offset.zero),
                  width: frame,
                  height: frame,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: SizedBox.square(
                        dimension: frame,
                        child: InteractiveViewer(
                          transformationController: _transform,
                          minScale: 1,
                          maxScale: 5,
                          boundaryMargin: EdgeInsets.zero,
                          constrained: false,
                          clipBehavior: Clip.none,
                          child: SizedBox(
                            width: child.width,
                            height: child.height,
                            child: Image.memory(
                              widget.cover.bytes,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(painter: _FramePainter(hole)),
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Pinch to zoom · drag to move',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dims everything outside [hole] and draws the frame with a thirds grid
/// (`.crop .frame` in the mockup).
class _FramePainter extends CustomPainter {
  const _FramePainter(this.hole);

  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(hole);
    canvas.drawPath(outside, Paint()..color = const Color(0x8c000000));
    final grid = Paint()
      ..color = const Color(0x73ffffff)
      ..strokeWidth = 1;
    for (final f in [1 / 3, 2 / 3]) {
      final x = hole.left + hole.width * f;
      final y = hole.top + hole.height * f;
      canvas.drawLine(Offset(x, hole.top), Offset(x, hole.bottom), grid);
      canvas.drawLine(Offset(hole.left, y), Offset(hole.right, y), grid);
    }
    canvas.drawRect(
      hole,
      Paint()
        ..color = const Color(0xe6ffffff)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.hole != hole;
}
