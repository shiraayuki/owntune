import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/player_sheet.dart';

/// Share of [durationMs] that [position] covers, clamped to 0..1; 0 for an
/// unknown or zero duration.
double progressOf(Duration position, int durationMs) => durationMs <= 0
    ? 0
    : (position.inMilliseconds / durationMs).clamp(0.0, 1.0).toDouble();

/// The floating mini player (`.mini`): cover, title, artist, play/pause and
/// a thin progress line. Hidden while nothing is loaded. Tap opens the
/// player; swipe left for the next song, right for the previous one.
///
/// It sits in a Scaffold's bottom bar, so menus and dialogs dim it with the
/// rest of the screen. Above the tab bar [overTabBar] is true; on pushed
/// screens it keeps clear of the home indicator itself.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key, this.overTabBar = false, this.onOpen});

  final bool overTabBar;

  /// Opens the full-screen player.
  final VoidCallback? onOpen;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  /// A swipe this far (share of the width) or this fast skips.
  static const _skipShare = 0.25;
  static const _skipVelocity = 700.0;

  /// Horizontal offset of the song while it is dragged.
  var _dx = 0.0;
  var _dragging = false;

  void _onDragUpdate(DragUpdateDetails d, {required bool hasNext}) {
    final next = _dx + d.delta.dx;
    // Resist where there is nothing to skip to.
    final resisted = next < 0 && !hasNext ? _dx + d.delta.dx * 0.3 : next;
    setState(() {
      _dragging = true;
      _dx = resisted;
    });
  }

  void _onDragEnd(DragEndDetails d, {required bool hasNext}) {
    final width = context.size?.width ?? 1;
    final velocity = d.primaryVelocity ?? 0;
    final far = _dx.abs() > width * _skipShare;
    final player = ref.read(playerProvider.notifier);
    if (_dx < 0 && hasNext && (far || velocity < -_skipVelocity)) {
      player.next();
    } else if (_dx > 0 && (far || velocity > _skipVelocity)) {
      player.skipBack();
    }
    setState(() {
      _dragging = false;
      _dx = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) return const SizedBox.shrink();
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final storage = ref.watch(storageProvider);
    final playing = ref.watch(playerProvider.select((s) => s.playing));
    final hasNext = ref.watch(playerProvider.select((s) => s.queue.hasNext));
    final player = ref.read(playerProvider.notifier);
    final cover = track.coverFile;
    final bottom = widget.overTabBar
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, bottom + 8),
      child: GestureDetector(
        key: const Key('mini-player'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen ?? () => showPlayer(context),
        onHorizontalDragUpdate: (d) => _onDragUpdate(d, hasNext: hasNext),
        onHorizontalDragEnd: (d) => _onDragEnd(d, hasNext: hasNext),
        onHorizontalDragCancel: () => setState(() {
          _dragging = false;
          _dx = 0;
        }),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, dark ? 0.28 : 0.12),
                blurRadius: dark ? 26 : 20,
                offset: Offset(0, dark ? 8 : 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dark
                      ? c.surface2.withValues(alpha: 0.88)
                      : const Color.fromRGBO(255, 255, 255, 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.line, width: 0.5),
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: AnimatedContainer(
                              duration: _dragging
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              transform: Matrix4.translationValues(_dx, 0, 0),
                              child: Row(
                                children: [
                                  Artwork(
                                    file: cover == null
                                        ? null
                                        : storage.coverFile(cover),
                                    size: 44,
                                    radius: 8,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayTitle(
                                            track.title,
                                            track.originalName,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: c.text,
                                          ),
                                        ),
                                        Text(
                                          displayArtist(track.artist),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: c.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _MiniButton(
                            key: const Key('mini-play'),
                            icon: playing
                                ? CupertinoIcons.pause_fill
                                : CupertinoIcons.play_fill,
                            tooltip: playing ? 'Pause' : 'Play',
                            onPressed: player.togglePlay,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 0,
                      child: _ProgressLine(durationMs: track.durationMs),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 26),
      color: c.text,
      disabledColor: c.faint,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
    );
  }
}

/// 2pt line, accent on fill, for the share of the song already played.
class _ProgressLine extends ConsumerWidget {
  const _ProgressLine({required this.durationMs});

  final int durationMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    return Container(
      height: 2,
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: BorderRadius.circular(1),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progressOf(position, durationMs),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}
