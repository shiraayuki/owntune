import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoDialogAction, CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/import/import_controller.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/section_index.dart';
import 'package:owntune/library/song_sort.dart';
import 'package:owntune/library/sort_key.dart';

/// The Songs tab: all tracks in the chosen order with letter sections, or
/// the empty state.
class SongsScreen extends ConsumerWidget {
  const SongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(settingsProvider.select((s) => s.songSort));
    return ref
        .watch(sortedSongsProvider)
        .when(
          data: (songs) => songs.isEmpty
              ? const EmptyLibrary()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Meta(count: songs.length, sort: sort),
                    Expanded(
                      child: SongList(songs: songs, sort: sort),
                    ),
                  ],
                ),
          error: (e, _) => _LoadError(message: e.toString()),
          loading: () => const SizedBox.shrink(),
        );
  }
}

/// `m:ss`, e.g. 251000 → `4:11`.
String formatDuration(int ms) {
  final seconds = ms ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// "47 songs · sorted by title" (`.meta`).
class _Meta extends StatelessWidget {
  const _Meta({required this.count, required this.sort});

  final int count;
  final SongSort sort;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Text(
        '$count ${count == 1 ? 'song' : 'songs'} · sorted by ${sortLabel(sort)}',
        style: TextStyle(fontSize: 13, color: c.muted),
      ),
    );
  }
}

/// Sorted songs with a section header wherever the [sort]'s section letter
/// changes (none for sorts without sections), plus the A–Z index when there
/// are sections.
class SongList extends StatefulWidget {
  const SongList({super.key, required this.songs, required this.sort});

  /// Already in [sort] order.
  final List<Track> songs;
  final SongSort sort;

  @override
  State<SongList> createState() => _SongListState();
}

class _SongListState extends State<SongList> {
  static const _headerExtent = 36.0;
  static const _rowExtent = 64.0;

  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <Object>[];
    // Scroll offset of each section header.
    final offsets = <String, double>{};
    var offset = 0.0;
    String? letter;
    for (final t in widget.songs) {
      final l = songSection(t, widget.sort);
      if (l != null && l != letter) {
        items.add(letter = l);
        offsets.putIfAbsent(l, () => offset);
        offset += _headerExtent;
      }
      items.add(t);
      offset += _rowExtent;
    }
    final indexed = offsets.isNotEmpty;

    final list = ListView.builder(
      controller: _controller,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        indexed ? 26 : 16,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      itemCount: items.length,
      itemExtentBuilder: (i, _) =>
          i < items.length && items[i] is String ? _headerExtent : _rowExtent,
      itemBuilder: (context, i) => switch (items[i]) {
        final Track t => SongRow(track: t, divider: i + 1 < items.length),
        final String l => _SectionHeader(
          key: ValueKey('section-$l'),
          letter: l,
        ),
        _ => const SizedBox.shrink(),
      },
    );
    if (!indexed) return list;

    return Stack(
      children: [
        list,
        Positioned(
          right: 2,
          top: 0,
          bottom: MediaQuery.paddingOf(context).bottom,
          child: SectionIndex(
            available: offsets.keys.toSet(),
            onSelect: (l) {
              final target = jumpTarget(l, offsets.keys.toSet());
              if (target == null || !_controller.hasClients) return;
              final position = _controller.position;
              _controller.jumpTo(
                offsets[target]!.clamp(0.0, position.maxScrollExtent),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: c.accent,
          ),
        ),
      ),
    );
  }
}

/// 64pt row: 48pt artwork, title and `artist · album`.
class SongRow extends ConsumerWidget {
  const SongRow({super.key, required this.track, this.divider = true});

  final Track track;
  final bool divider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final storage = ref.watch(storageProvider);
    final cover = track.coverFile;
    final album = track.album?.trim();
    final subtitle = [
      displayArtist(track.artist),
      if (album != null && album.isNotEmpty) album,
    ].join(' · ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) =>
          showSongMenu(context, ref, track, details.globalPosition),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Artwork(
                    file: cover == null ? null : storage.coverFile(cover),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayTitle(track.title, track.originalName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (divider)
              Positioned(
                left: 60,
                right: 0,
                bottom: 0,
                child: Container(height: 0.5, color: c.line),
              ),
          ],
        ),
      ),
    );
  }
}

/// iOS system red (`--red` in the mockup), light and dark.
Color _red(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xffff453a)
    : const Color(0xffff3b30);

enum _SongAction { delete }

/// The long-press context menu of a song row, opened at [position].
///
/// The row may be rebuilt elsewhere (and its element disposed) while a menu
/// or dialog is open, e.g. by a running import; so the repository and the
/// navigator are captured before the first await.
Future<void> showSongMenu(
  BuildContext context,
  WidgetRef ref,
  Track track,
  Offset position,
) async {
  final repo = ref.read(trackRepositoryProvider);
  final navigator = Navigator.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final red = _red(context);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final action = await showMenu<_SongAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & overlay.size,
    ),
    color: dark
        ? const Color.fromRGBO(37, 37, 42, 0.96)
        : const Color.fromRGBO(250, 250, 250, 0.96),
    elevation: 12,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    constraints: const BoxConstraints.tightFor(width: 250),
    menuPadding: EdgeInsets.zero,
    items: [
      PopupMenuItem(
        value: _SongAction.delete,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Delete from Library',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, color: red),
              ),
            ),
            const SizedBox(width: 10),
            Icon(CupertinoIcons.trash, size: 20, color: red),
          ],
        ),
      ),
    ],
  );
  if (action == _SongAction.delete && navigator.mounted) {
    await confirmDeleteSong(navigator.context, repo, track);
  }
}

/// Asks before deleting [track]; only `Delete` removes it from the library.
/// A failure is shown in a dialog (there are no logs on the iPhone).
///
/// [context] must stay mounted across the dialogs (the navigator's context).
Future<void> confirmDeleteSong(
  BuildContext context,
  TrackRepository repo,
  Track track,
) async {
  final title = displayTitle(track.title, track.originalName);
  final confirmed = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text('Delete "$title"?'),
      content: const Text(
        'The song will be removed from owntune and its file deleted.',
      ),
      actions: [
        _DialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
        ),
        _DialogAction(
          label: 'Delete',
          destructive: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return;
  try {
    await repo.delete(track.id);
  } catch (e) {
    if (!context.mounted) return;
    await showAdaptiveDialog<void>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text('Could not delete "$title"'),
        content: SelectableText('$e'),
        actions: [
          _DialogAction(label: 'OK', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

/// A dialog button: Cupertino on iOS/macOS, a text button elsewhere.
class _DialogAction extends StatelessWidget {
  const _DialogAction({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return CupertinoDialogAction(
          isDestructiveAction: destructive,
          onPressed: onPressed,
          child: Text(label),
        );
      default:
        return TextButton(
          style: destructive
              ? TextButton.styleFrom(foregroundColor: _red(context))
              : null,
          onPressed: onPressed,
          child: Text(label),
        );
    }
  }
}

/// Shown when the library has no songs.
class EmptyLibrary extends ConsumerWidget {
  const EmptyLibrary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final running = ref.watch(importControllerProvider) is ImportRunning;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 44, 120),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Disc(),
                  const SizedBox(height: 26),
                  Text(
                    'Your library is empty',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Import music files from your phone. owntune copies them '
                    'into its own library, so they stay available offline.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, color: c.muted),
                  ),
                  const SizedBox(height: 24),
                  PillButton(
                    icon: CupertinoIcons.plus,
                    label: 'Import Music',
                    onPressed: running
                        ? null
                        : () => ref
                              .read(importControllerProvider.notifier)
                              .pickAndImport(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'MP3 · M4A/AAC · FLAC · WAV',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The record graphic of the empty state (`.disc-art`).
class _Disc extends StatelessWidget {
  const _Disc();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.line, width: 0.5),
        // CSS `radial-gradient(circle, …)` sizes to the farthest corner,
        // i.e. sqrt(2) × half the side.
        gradient: RadialGradient(
          radius: 0.7071,
          colors: [c.bg, c.bg, c.surface2, c.surface2, c.surface, c.surface],
          stops: const [0, 0.14, 0.15, 0.18, 0.19, 1],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load your library',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
