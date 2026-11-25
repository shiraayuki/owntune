import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/player/player_controller.dart';

/// The big cover in Now Playing. Swipe left for the next song, right for the
/// previous one (on the first song: restart), like the mini player; the
/// neighbour's cover slides in beside it while dragging.
class CoverCarousel extends ConsumerStatefulWidget {
  const CoverCarousel({super.key, required this.side});

  /// Width and height of one cover.
  final double side;

  @override
  ConsumerState<CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends ConsumerState<CoverCarousel>
    with SingleTickerProviderStateMixin {
  /// A swipe this far (share of the cover) or this fast skips; as in the
  /// mini player.
  static const _skipShare = 0.25;
  static const _skipVelocity = 700.0;

  /// Space between the covers.
  static const _gap = 24.0;

  static const _settle = Duration(milliseconds: 180);

  /// Horizontal offset of the covers.
  late final _dx = AnimationController.unbounded(vsync: this);

  /// True while a committed swipe slides out; drags wait for it.
  var _committing = false;

  double get _step => widget.side + _gap;

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    if (!_committing) _dx.stop();
  }

  void _onDragUpdate(DragUpdateDetails d, {required bool hasNext}) {
    if (_committing) return;
    final next = _dx.value + d.delta.dx;
    // Resist where there is nothing to skip to.
    _dx.value = next < 0 && !hasNext ? _dx.value + d.delta.dx * 0.3 : next;
  }

  void _onDragEnd(
    DragEndDetails d, {
    required bool hasNext,
    required bool hasPrevious,
  }) {
    if (_committing) return;
    final dx = _dx.value;
    final velocity = d.primaryVelocity ?? 0;
    final far = dx.abs() > widget.side * _skipShare;
    final player = ref.read(playerProvider.notifier);
    if (dx < 0 && hasNext && (far || velocity < -_skipVelocity)) {
      _commit(-_step, player.next);
    } else if (dx > 0 && (far || velocity > _skipVelocity)) {
      if (hasPrevious) {
        _commit(_step, player.skipBack);
      } else {
        // The first song restarts; there is no cover to slide to.
        player.skipBack();
        _springBack();
      }
    } else {
      _springBack();
    }
  }

  /// Slides the neighbour into place, then switches the song. The controller
  /// changes the current song synchronously, so the reset to 0 lands in the
  /// same frame as the new cover.
  void _commit(double target, Future<void> Function() skip) {
    _committing = true;
    _dx
        .animateTo(target, duration: _settle, curve: Curves.easeOut)
        .whenCompleteOrCancel(() {
          if (!mounted) return;
          skip();
          _dx.value = 0;
          _committing = false;
        });
  }

  void _springBack() =>
      _dx.animateTo(0, duration: _settle, curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(playerProvider.select((s) => s.queue));
    final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
    final storage = ref.watch(storageProvider);
    Track? at(int? index) {
      if (index == null) return null;
      final id = queue.entries[index].trackId;
      for (final t in tracks) {
        if (t.id == id) return t;
      }
      return null;
    }

    final current = at(queue.current == null ? null : queue.index);
    final hasNext = queue.hasNext;
    final next = hasNext ? at(queue.nextIndex(auto: false)) : null;
    final hasPrevious = queue.previousIndex != null;
    final previous = at(queue.previousIndex);
    final side = widget.side;

    Widget cover(Track? t, {Key? key}) => KeyedSubtree(
      key: key,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.45),
              blurRadius: 60,
              offset: Offset(0, 24),
            ),
          ],
        ),
        child: Artwork(
          file: t?.coverFile == null ? null : storage.coverFile(t!.coverFile!),
          size: side,
          radius: 14,
        ),
      ),
    );

    return GestureDetector(
      key: const Key('player-cover'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: (d) => _onDragUpdate(d, hasNext: hasNext),
      onHorizontalDragEnd: (d) =>
          _onDragEnd(d, hasNext: hasNext, hasPrevious: hasPrevious),
      onHorizontalDragCancel: () {
        if (!_committing) _springBack();
      },
      child: SizedBox.square(
        dimension: side,
        child: AnimatedBuilder(
          animation: _dx,
          builder: (context, child) {
            final dx = _dx.value;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Neighbours only while they can show, so an idle player
                // draws one cover.
                if (previous != null && dx > 0)
                  Positioned(
                    left: dx - _step,
                    top: 0,
                    child: cover(
                      previous,
                      key: const Key('player-cover-previous'),
                    ),
                  ),
                Positioned(left: dx, top: 0, child: child!),
                if (next != null && dx < 0)
                  Positioned(
                    left: dx + _step,
                    top: 0,
                    child: cover(next, key: const Key('player-cover-next')),
                  ),
              ],
            );
          },
          child: cover(current),
        ),
      ),
    );
  }
}
