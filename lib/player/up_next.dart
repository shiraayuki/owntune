import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/play_queue.dart';
import 'package:owntune/player/player_controller.dart';

/// The queue view inside the player (mockup 10): "Up Next" with Clear, where
/// the queue was started from, and the upcoming songs. Drag the grip to
/// reorder, swipe left to remove, tap to play.
class UpNext extends ConsumerWidget {
  const UpNext({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final queue = ref.watch(playerProvider.select((s) => s.queue));
    final tracks = {
      for (final t in ref.watch(tracksProvider).value ?? const <Track>[])
        t.id: t,
    };
    final player = ref.read(playerProvider.notifier);
    final upcoming = queue.upcoming;
    final source = queue.source?.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Up Next',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              GestureDetector(
                key: const Key('up-next-clear'),
                behavior: HitTestBehavior.opaque,
                onTap: upcoming.isEmpty ? null : player.clearUpcoming,
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 17,
                    color: upcoming.isEmpty ? c.faint : c.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (source != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              'Playing from $source',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: upcoming.length,
            onReorderItem: player.moveUpcoming,
            itemBuilder: (context, i) {
              final entry = upcoming[i];
              return _UpNextRow(
                key: ValueKey('up-next-row-${entry.key}'),
                entry: entry,
                index: i,
                track: tracks[entry.trackId],
                divider: i + 1 < upcoming.length,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UpNextRow extends ConsumerWidget {
  const _UpNextRow({
    super.key,
    required this.entry,
    required this.index,
    required this.track,
    required this.divider,
  });

  final QueueEntry entry;
  final int index;

  /// Null for a moment after the song was deleted, until the queue follows.
  final Track? track;
  final bool divider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final storage = ref.watch(storageProvider);
    final player = ref.read(playerProvider.notifier);
    final track = this.track;
    final cover = track?.coverFile;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final red = dark ? const Color(0xffff453a) : const Color(0xffff3b30);

    return Dismissible(
      key: ValueKey('up-next-dismiss-${entry.key}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => player.remove(entry.key),
      background: Container(
        color: red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Text(
          'Remove',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xffffffff),
          ),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => player.jumpTo(entry.key),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Artwork(
                        file: cover == null ? null : storage.coverFile(cover),
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track == null
                                  ? ''
                                  : displayTitle(
                                      track.title,
                                      track.originalName,
                                    ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: c.text,
                              ),
                            ),
                            Text(
                              track == null ? '' : displayArtist(track.artist),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            CupertinoIcons.line_horizontal_3,
                            size: 22,
                            color: c.faint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (divider)
                  Positioned(
                    left: 52,
                    right: 0,
                    bottom: 0,
                    child: Container(height: 0.5, color: c.line),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
