import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoDialogAction, CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/edit/edit_info_screen.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/import/import_controller.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/search.dart';
import 'package:owntune/library/search_screen.dart';
import 'package:owntune/library/section_index.dart';
import 'package:owntune/library/song_sort.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/playlists/add_to_playlist_sheet.dart';

/// The Songs tab: all tracks in the chosen order with letter sections, or
/// the empty state.
class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _list(List<Track> songs, SongSort sort) {
    final selection = ref.watch(songSelectionProvider);
    void toggle(Track t) =>
        ref.read(songSelectionProvider.notifier).toggle(t.id);
    final q = foldKey(_query.text);
    if (q.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Meta(count: songs.length, sort: sort, selecting: selection != null),
          Expanded(
            child: SongList(
              songs: songs,
              sort: sort,
              source: 'Songs',
              selection: selection,
              onToggle: toggle,
            ),
          ),
        ],
      );
    }
    final matches = songs.where((t) => songMatches(t, q)).toList();
    return matches.isEmpty
        ? NoResults(query: _query.text)
        : SongList(
            songs: matches,
            sort: sort,
            sections: false,
            source: 'Songs',
            selection: selection,
            onToggle: toggle,
          );
  }

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(settingsProvider.select((s) => s.songSort));
    return ref
        .watch(sortedSongsProvider)
        .when(
          data: (songs) => songs.isEmpty
              ? const EmptyLibrary()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TabSearchField(label: 'Search Songs', controller: _query),
                    Expanded(child: _list(songs, sort)),
                  ],
                ),
          error: (e, _) => LoadError(message: e.toString()),
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
  const _Meta({
    required this.count,
    required this.sort,
    required this.selecting,
  });

  final int count;
  final SongSort sort;
  final bool selecting;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final songs = '$count ${count == 1 ? 'song' : 'songs'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Text(
        selecting
            ? '$songs · tap to select'
            : '$songs · sorted by ${sortLabel(sort)}',
        style: TextStyle(fontSize: 13, color: c.muted),
      ),
    );
  }
}

/// Sorted songs with a section header wherever the [sort]'s section letter
/// changes (none for sorts without sections), plus the A–Z index when there
/// are sections.
class SongList extends ConsumerStatefulWidget {
  const SongList({
    super.key,
    required this.songs,
    required this.sort,
    required this.source,
    this.sections = true,
    this.selection,
    this.onToggle,
  });

  /// Already in [sort] order.
  final List<Track> songs;
  final SongSort sort;

  /// False for a filtered list: no section headers and no index.
  final bool sections;

  /// "Playing from" label of the queue a tap starts.
  final String source;

  /// The selected ids while selecting (rows show check circles and a tap
  /// calls [onToggle] instead of playing); null otherwise.
  final Set<int>? selection;
  final ValueChanged<Track>? onToggle;

  @override
  ConsumerState<SongList> createState() => _SongListState();
}

class _SongListState extends ConsumerState<SongList> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final headerExtent = sectionHeaderExtent(scaler);
    final rowExtent = SongRow.extentFor(scaler);
    final items = <Object>[];
    // Scroll offset of each section header.
    final offsets = <String, double>{};
    var offset = 0.0;
    String? letter;
    // Position in widget.songs of each Track in items.
    final songIndex = <int, int>{};
    for (final (j, t) in widget.songs.indexed) {
      final l = widget.sections ? songSection(t, widget.sort) : null;
      if (l != null && l != letter) {
        items.add(letter = l);
        offsets.putIfAbsent(l, () => offset);
        offset += headerExtent;
      }
      songIndex[items.length] = j;
      items.add(t);
      offset += rowExtent;
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
          i < items.length && items[i] is String ? headerExtent : rowExtent,
      itemBuilder: (context, i) => switch (items[i]) {
        final Track t => SongRow(
          track: t,
          scope: const SongMenuScope(backLabel: 'Library'),
          divider: i + 1 < items.length,
          selected: widget.selection?.contains(t.id),
          onTap: widget.selection != null
              ? () => widget.onToggle?.call(t)
              : () => ref
                    .read(playerProvider.notifier)
                    .playList(
                      widget.songs,
                      start: songIndex[i]!,
                      source: widget.source,
                    ),
        ),
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

/// Line height (as a multiple of the font size) of song rows and section
/// headers; fixed so their extents can be computed for the A–Z index.
const _lineHeight = 1.2;

/// Rendered height of one text line of [fontSize] at [scaler]; text layout
/// rounds line heights up to whole pixels.
double _line(TextScaler scaler, double fontSize) =>
    (scaler.scale(fontSize) * _lineHeight).ceilToDouble();

/// Height of a section header at [scaler]: 14pt above, 2pt below the letter.
double sectionHeaderExtent(TextScaler scaler) =>
    math.max(36, 16 + _line(scaler, 15));

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
            height: _lineHeight,
            fontWeight: FontWeight.w800,
            color: c.accent,
          ),
        ),
      ),
    );
  }
}

/// 64pt row: 48pt artwork, title and `artist · album` (or [subtitle]).
class SongRow extends ConsumerWidget {
  const SongRow({
    super.key,
    required this.track,
    required this.scope,
    this.divider = true,
    this.subtitle,
    this.onTap,
    this.selected,
  });

  final Track track;
  final SongMenuScope scope;
  final bool divider;

  /// Non-null in selection mode: shows the check circle (filled when true)
  /// and turns the long-press menu off.
  final bool? selected;

  /// Replaces the default `artist · album` line.
  final String? subtitle;

  /// Plays the song, usually with its list as the queue.
  final VoidCallback? onTap;

  /// Height of a row at [scaler]: 64pt, more when the two text lines need
  /// it.
  static double extentFor(TextScaler scaler) =>
      math.max(64, 16 + _line(scaler, 17) + _line(scaler, 15));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final storage = ref.watch(storageProvider);
    final playing = ref.watch(
      currentTrackProvider.select((t) => t?.id == track.id),
    );
    final cover = track.coverFile;
    final album = track.album?.trim();
    final subtitle =
        this.subtitle ??
        [
          displayArtist(track.artist),
          if (album != null && album.isNotEmpty) album,
        ].join(' · ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPressStart: selected != null
          ? null
          : (details) => showSongMenu(
              context,
              ref,
              track,
              details.globalPosition,
              scope,
            ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  if (selected case final on?) ...[
                    _Check(key: Key('song-check-${track.id}'), on: on),
                    const SizedBox(width: 12),
                  ],
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
                            height: _lineHeight,
                            fontWeight: FontWeight.w600,
                            color: playing ? c.accent : c.text,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: _lineHeight,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected == null)
                    SongMoreButton(
                      key: Key('song-more-${track.id}'),
                      onPressed: (at) =>
                          showSongMenu(context, ref, track, at, scope),
                    ),
                ],
              ),
            ),
            if (divider)
              Positioned(
                left: selected == null ? 60 : 96,
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

/// The trailing "…" of a song row: opens the song menu at the button's
/// bottom-right corner. [onPressed] gets that corner in global coordinates.
class SongMoreButton extends StatelessWidget {
  const SongMoreButton({super.key, required this.onPressed});

  final void Function(Offset globalPosition) onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Semantics(
      container: true,
      button: true,
      label: 'More',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final box = context.findRenderObject()! as RenderBox;
          onPressed(box.localToGlobal(box.size.bottomRight(Offset.zero)));
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Icon(CupertinoIcons.ellipsis, size: 20, color: c.muted),
          ),
        ),
      ),
    );
  }
}

/// The 24pt check circle of a row in selection mode (`.chk`).
class _Check extends StatelessWidget {
  const _Check({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? c.accent : null,
        border: Border.all(color: on ? c.accent : c.faint, width: 1.5),
      ),
      child: on
          ? Icon(CupertinoIcons.checkmark, size: 14, color: c.accentText)
          : null,
    );
  }
}

/// iOS system red (`--red` in the mockup), light and dark.
Color _red(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xffff453a)
    : const Color(0xffff3b30);

enum _SongAction {
  playNext,
  playLater,
  addToPlaylist,
  album,
  artist,
  edit,
  removeFromPlaylist,
  delete,
}

/// Where a song row is shown, for its context menu: the back label of
/// screens it opens, and the album/artist screen it is already on (whose
/// "Go to" entry is left out).
class SongMenuScope {
  const SongMenuScope({
    required this.backLabel,
    this.currentAlbum,
    this.currentArtist,
    this.inPlayer = false,
    this.playlistEntry,
  });

  final String backLabel;
  final AlbumKey? currentAlbum;
  final String? currentArtist;

  /// Opened from the player: no Play Next/Later, and "Go to" closes the
  /// player before it opens the screen.
  final bool inPlayer;

  /// The playlist entry this row shows: adds "Remove from Playlist".
  final ({int playlistId, int entryId})? playlistEntry;
}

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
  SongMenuScope scope,
) async {
  final repo = ref.read(trackRepositoryProvider);
  final player = ref.read(playerProvider.notifier);
  final playlists = ref.read(playlistRepositoryProvider);
  final navigator = Navigator.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final fg = dark ? const Color(0xffffffff) : const Color(0xff000000);
  final red = _red(context);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final albumKey = albumKeyOf(track);
  final artistKey = artistGroupKey(track.artist);
  final showAlbum = albumKey != null && albumKey != scope.currentAlbum;
  final showArtist = artistKey != scope.currentArtist;

  PopupMenuItem<_SongAction> item(
    _SongAction value,
    String label,
    IconData icon,
    Color color, {
    Key? key,
  }) => PopupMenuItem(
    key: key,
    value: value,
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17, color: color),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 20, color: color),
      ],
    ),
  );

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
      if (!scope.inPlayer) ...[
        item(
          _SongAction.playNext,
          'Play Next',
          CupertinoIcons.text_insert,
          fg,
          key: const Key('menu-play-next'),
        ),
        item(
          _SongAction.playLater,
          'Play Later',
          CupertinoIcons.text_append,
          fg,
          key: const Key('menu-play-later'),
        ),
      ],
      item(
        _SongAction.addToPlaylist,
        'Add to Playlist…',
        CupertinoIcons.text_badge_plus,
        fg,
        key: const Key('menu-add-to-playlist'),
      ),
      menuGap(context),
      if (showAlbum)
        item(_SongAction.album, 'Go to Album', CupertinoIcons.square_stack, fg),
      if (showArtist)
        item(_SongAction.artist, 'Go to Artist', CupertinoIcons.person, fg),
      if (showAlbum || showArtist) menuGap(context),
      item(
        _SongAction.edit,
        'Edit Info',
        CupertinoIcons.pencil,
        fg,
        key: const Key('menu-edit'),
      ),
      menuGap(context),
      if (scope.playlistEntry != null)
        item(
          _SongAction.removeFromPlaylist,
          'Remove from Playlist',
          CupertinoIcons.minus_circle,
          fg,
          key: const Key('menu-remove-from-playlist'),
        ),
      item(
        _SongAction.delete,
        'Delete from Library',
        CupertinoIcons.trash,
        red,
      ),
    ],
  );
  if (!navigator.mounted) return;
  if (scope.inPlayer &&
      (action == _SongAction.album || action == _SongAction.artist)) {
    navigator.pop();
  }
  switch (action) {
    case _SongAction.playNext:
      await player.playNext(track);
    case _SongAction.playLater:
      await player.playLater(track);
    case _SongAction.addToPlaylist:
      await showAddToPlaylist(navigator.context, [track]);
    case _SongAction.album:
      await openAlbum(navigator.context, albumKey!, backLabel: scope.backLabel);
    case _SongAction.artist:
      await openArtist(
        navigator.context,
        artistKey,
        backLabel: scope.backLabel,
      );
    case _SongAction.edit:
      await openEditInfo(navigator.context, [track]);
    case _SongAction.removeFromPlaylist:
      try {
        await playlists.removeEntry(scope.playlistEntry!.entryId);
      } catch (e) {
        if (!navigator.mounted) return;
        await showAdaptiveDialog<void>(
          context: navigator.context,
          builder: (context) => AlertDialog.adaptive(
            title: const Text('Could not remove the song'),
            content: SelectableText('$e'),
            actions: [
              DialogAction(
                label: 'OK',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    case _SongAction.delete:
      await confirmDeleteSong(navigator.context, repo, track);
    case null:
      break;
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
        DialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
        ),
        DialogAction(
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
          DialogAction(label: 'OK', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

/// Asks before deleting [tracks]; true when the user confirmed. Deletes them
/// one by one and lists the songs that could not be deleted in one dialog.
///
/// [context] must stay mounted across the dialogs (the navigator's context).
Future<bool> confirmDeleteSongs(
  BuildContext context,
  TrackRepository repo,
  List<Track> tracks,
) async {
  String songs(int n) => n == 1 ? '1 song' : '$n songs';
  final confirmed = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text('Delete ${songs(tracks.length)}?'),
      content: Text(
        tracks.length == 1
            ? 'The song will be removed from owntune and its file deleted.'
            : 'The songs will be removed from owntune and their files deleted.',
      ),
      actions: [
        DialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
        ),
        DialogAction(
          label: 'Delete',
          destructive: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return false;
  final failures = <String>[];
  for (final t in tracks) {
    try {
      await repo.delete(t.id);
    } on Object catch (e) {
      failures.add('${displayTitle(t.title, t.originalName)}: $e');
    }
  }
  if (failures.isNotEmpty && context.mounted) {
    await showAdaptiveDialog<void>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text("Couldn't delete ${songs(failures.length)}"),
        content: SingleChildScrollView(
          child: SelectableText(failures.join('\n')),
        ),
        actions: [
          DialogAction(label: 'OK', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
  return true;
}

/// A dialog button: Cupertino on iOS/macOS, a text button elsewhere.
/// A dialog button: Cupertino style on iOS/macOS, a text button elsewhere.
class DialogAction extends StatelessWidget {
  const DialogAction({
    super.key,
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

/// A failed database load, shown as selectable text (no logs on the iPhone).
class LoadError extends StatelessWidget {
  const LoadError({
    super.key,
    required this.message,
    this.title = 'Could not load your library',
  });

  final String title;
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
              title,
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
