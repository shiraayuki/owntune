import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/library/songs_screen.dart' show formatDuration;
import 'package:owntune/player/mini_player.dart' show progressOf;
import 'package:owntune/player/player_controller.dart';

/// The player's scrubber (`.scrub`): a 5pt track with elapsed and
/// `-remaining` time. While dragging, the labels follow the finger; the
/// player seeks only on release.
/// Diameter of the dot at the current position.
const _thumb = 12.0;

class Scrubber extends ConsumerStatefulWidget {
  const Scrubber({super.key, required this.durationMs});

  final int durationMs;

  @override
  ConsumerState<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends ConsumerState<Scrubber> {
  /// Fraction under the finger while dragging, else null.
  double? _drag;

  double _fractionAt(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  void _release() {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = null);
    if (widget.durationMs <= 0) return;
    ref
        .read(playerProvider.notifier)
        .seek(Duration(milliseconds: (drag * widget.durationMs).round()));
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    final fraction = _drag ?? progressOf(position, widget.durationMs);
    final elapsedMs = (fraction * widget.durationMs).round();
    final remainingMs = widget.durationMs - elapsedMs;
    final times = TextStyle(
      fontSize: 13,
      color: c.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          key: const Key('scrubber'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) =>
              setState(() => _drag = _fractionAt(d.localPosition, width)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _drag = _fractionAt(d.localPosition, width)),
          onHorizontalDragEnd: (_) => _release(),
          onHorizontalDragCancel: () => setState(() => _drag = null),
          onTapUp: (d) {
            _drag = _fractionAt(d.localPosition, width);
            _release();
          },
          child: Padding(
            // A taller hit area than the 5pt track.
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The track with a dot at the current position (as in
                // Spotify).
                SizedBox(
                  height: _thumb,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        key: const Key('scrubber-track'),
                        height: 5,
                        decoration: BoxDecoration(
                          color: c.fill,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: fraction,
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.text.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: fraction * width - _thumb / 2,
                        child: DecoratedBox(
                          key: const Key('scrubber-thumb'),
                          decoration: BoxDecoration(
                            color: c.text,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: _thumb),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDuration(elapsedMs), style: times),
                    Text('-${formatDuration(remainingMs)}', style: times),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
