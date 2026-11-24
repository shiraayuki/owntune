import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/songs_screen.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/play_queue.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/scrubber.dart';
import 'package:owntune/player/up_next.dart';

/// Opens Now Playing as a full-screen sheet; swipe down or tap the grabber
/// to close it.
Future<void> showPlayer(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: false,
  enableDrag: true,
  useRootNavigator: true,
  backgroundColor: Colors.transparent,
  builder: (_) => const PlayerSheet(),
);

/// Now Playing (mockup 09): blurred cover backdrop, cover, title, scrubber,
/// controls and the Up Next pill.
class PlayerSheet extends ConsumerStatefulWidget {
  const PlayerSheet({super.key});

  @override
  ConsumerState<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<PlayerSheet> {
  var _showQueue = false;

  void _close() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      // A dialog (e.g. the delete confirmation) sits above the sheet.
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentTrackProvider, (_, next) {
      if (next == null) _close();
    });
    final track = ref.watch(currentTrackProvider);
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final storage = ref.watch(storageProvider);
    final cover = track?.coverFile;
    final coverFile = cover == null ? null : storage.coverFile(cover);
    final padding = MediaQuery.viewPaddingOf(context);
    // The sheet route (and the Scaffold bar the player opens from) remove the
    // top padding from the MediaQuery; the screen's own inset is the status
    // bar / Dynamic Island.
    final topInset = MediaQueryData.fromView(View.of(context)).viewPadding.top;

    return SizedBox(
      key: const Key('player-sheet'),
      height: MediaQuery.sizeOf(context).height,
      child: ClipRect(
        child: ColoredBox(
          color: c.bg,
          child: Stack(
            children: [
              if (coverFile != null)
                Positioned.fill(
                  child: Opacity(
                    opacity: dark ? 0.55 : 0.28,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                      child: Image.file(
                        coverFile,
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        c.bg.withValues(alpha: 0),
                        c.bg.withValues(alpha: 0.7),
                      ],
                      stops: const [0, 0.92],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: topInset,
                  bottom: padding.bottom + 16,
                ),
                child: track == null
                    ? const SizedBox.shrink()
                    : _Content(
                        track: track,
                        coverFile: coverFile,
                        showQueue: _showQueue,
                        onClose: _close,
                        onToggleQueue: () =>
                            setState(() => _showQueue = !_showQueue),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.track,
    required this.coverFile,
    required this.showQueue,
    required this.onClose,
    required this.onToggleQueue,
  });

  final Track track;
  final File? coverFile;
  final bool showQueue;
  final VoidCallback onClose;
  final VoidCallback onToggleQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final album = track.album?.trim();
    final subtitle = [
      displayArtist(track.artist),
      if (album != null && album.isNotEmpty) album,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Down arrow (back to the mini player) and the song menu.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 16, 0),
          child: Row(
            children: [
              IconButton(
                key: const Key('player-close'),
                onPressed: onClose,
                tooltip: 'Close',
                icon: const Icon(CupertinoIcons.chevron_down, size: 26),
                color: c.text,
                style: IconButton.styleFrom(fixedSize: const Size.square(44)),
              ),
              const Spacer(),
              _MoreButton(track: track),
            ],
          ),
        ),
        if (!showQueue) ...[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 18, 32, 0),
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = [
                      326.0,
                      constraints.maxWidth,
                      constraints.maxHeight,
                    ].reduce((a, b) => a < b ? a : b);
                    return DecoratedBox(
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
                      child: Artwork(file: coverFile, size: side, radius: 14),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 34, 32, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle(track.title, track.originalName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 19, color: c.muted),
                      ),
                    ],
                  ),
                ),
                _LikeButton(track: track),
              ],
            ),
          ),
        ] else ...[
          _NowRow(track: track, coverFile: coverFile),
          const Expanded(child: UpNext()),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
          child: Scrubber(durationMs: track.durationMs),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(26, 12, 26, 0),
          child: PlayerControls(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 26),
          child: Center(
            child: _UpNextPill(on: showQueue, onTap: onToggleQueue),
          ),
        ),
      ],
    );
  }
}

/// The heart next to the title: likes or unlikes the current song.
class _LikeButton extends ConsumerWidget {
  const _LikeButton({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final liked = track.likedAt != null;
    final navigator = Navigator.of(context);
    return IconButton(
      key: const Key('player-like'),
      tooltip: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
      icon: Icon(
        liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
        size: 26,
        color: liked ? c.accent : c.text,
      ),
      style: IconButton.styleFrom(fixedSize: const Size.square(44)),
      onPressed: () async {
        // Read on tap, and before the await: the sheet may be gone by then.
        final repo = ref.read(trackRepositoryProvider);
        try {
          await repo.setLiked([track.id], liked: !liked);
        } catch (e) {
          if (!navigator.mounted) return;
          await showLikeError(navigator.context, e);
        }
      },
    );
  }
}

/// The compact current-song row above Up Next (`.q-now`).
class _NowRow extends StatelessWidget {
  const _NowRow({required this.track, required this.coverFile});

  final Track track;
  final File? coverFile;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final album = track.album?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.3),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Artwork(file: coverFile, size: 64, radius: 10),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle(track.title, track.originalName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
                Text(
                  [
                    displayArtist(track.artist),
                    if (album != null && album.isNotEmpty) album,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "…" next to the title: the song menu of the current song.
class _MoreButton extends ConsumerWidget {
  const _MoreButton({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Builder(
    builder: (button) => RoundIconButton(
      key: const Key('player-more'),
      icon: CupertinoIcons.ellipsis,
      tooltip: 'More',
      onPressed: () {
        final box = button.findRenderObject()! as RenderBox;
        showSongMenu(
          button,
          ref,
          track,
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
          // The screen under the player is not known here.
          const SongMenuScope(backLabel: 'Back', inPlayer: true),
        );
      },
    ),
  );
}

/// Shuffle, previous, play/pause, next and repeat (`.p-ctrls`).
class PlayerControls extends ConsumerWidget {
  const PlayerControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final playing = ref.watch(playerProvider.select((s) => s.playing));
    final hasNext = ref.watch(playerProvider.select((s) => s.queue.hasNext));
    final repeat = ref.watch(playerProvider.select((s) => s.queue.repeat));
    final shuffled = ref.watch(playerProvider.select((s) => s.queue.shuffled));
    final player = ref.read(playerProvider.notifier);

    Widget toggle({
      required Key key,
      required IconData icon,
      required String tooltip,
      required bool on,
      VoidCallback? onPressed,
    }) => IconButton(
      key: key,
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      color: on ? (dark ? c.accent : c.bg) : c.muted,
      disabledColor: c.faint,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(44),
        backgroundColor: on
            ? (dark ? c.accent.withValues(alpha: 0.16) : c.text)
            : Colors.transparent,
      ),
    );

    Widget skip(Key key, IconData icon, String tooltip, VoidCallback? f) =>
        IconButton(
          key: key,
          onPressed: f,
          tooltip: tooltip,
          icon: Icon(icon, size: 38),
          color: c.text,
          disabledColor: c.faint,
          style: IconButton.styleFrom(fixedSize: const Size.square(56)),
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        toggle(
          key: const Key('player-shuffle'),
          icon: CupertinoIcons.shuffle,
          tooltip: 'Shuffle',
          on: shuffled,
          onPressed: player.toggleShuffle,
        ),
        skip(
          const Key('player-previous'),
          CupertinoIcons.backward_fill,
          'Previous',
          player.previous,
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.3),
                blurRadius: 26,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: IconButton(
            key: const Key('player-play'),
            onPressed: player.togglePlay,
            tooltip: playing ? 'Pause' : 'Play',
            icon: Icon(
              playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
              size: 34,
            ),
            color: c.accentText,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(76),
              backgroundColor: c.accent,
            ),
          ),
        ),
        skip(
          const Key('player-next'),
          CupertinoIcons.forward_fill,
          'Next',
          hasNext ? player.next : null,
        ),
        toggle(
          key: const Key('player-repeat'),
          icon: repeat == QueueRepeat.one
              ? CupertinoIcons.repeat_1
              : CupertinoIcons.repeat,
          tooltip: switch (repeat) {
            QueueRepeat.off => 'Repeat off',
            QueueRepeat.all => 'Repeat all',
            QueueRepeat.one => 'Repeat one',
          },
          on: repeat != QueueRepeat.off,
          onPressed: player.cycleRepeat,
        ),
      ],
    );
  }
}

class _UpNextPill extends StatelessWidget {
  const _UpNextPill({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final fg = on ? c.accentText : c.text;
    return Material(
      color: on ? c.accent : c.fill,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('player-up-next'),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.list_bullet, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(
                  'Up Next',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
