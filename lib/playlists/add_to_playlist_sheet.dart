import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/library/songs_screen.dart' show DialogAction;
import 'package:owntune/playlists/new_playlist_sheet.dart';
import 'package:owntune/playlists/playlist_artwork.dart';
import 'package:owntune/playlists/playlist_view.dart';

/// Opens the Add to Playlist sheet (mockup 14) for [tracks]. Adds them at
/// the end of the chosen playlist (asking first when songs are already
/// there) or of a new one, and confirms in a SnackBar. True when something
/// was added.
Future<bool> showAddToPlaylist(BuildContext context, List<Track> tracks) async {
  if (tracks.isEmpty) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final name = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddToPlaylistSheet(tracks: tracks),
  );
  if (name == null) return false;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Added to $name'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  return true;
}

/// What to do with songs the playlist already has.
enum _Duplicates { cancel, onlyNew, all }

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() =>
      _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  /// A playlist is being written; taps are ignored meanwhile.
  var _busy = false;

  List<int> get _ids => [for (final t in widget.tracks) t.id];

  String get _subtitle {
    final tracks = widget.tracks;
    if (tracks.length == 1) {
      final t = tracks.single;
      return '“${displayTitle(t.title, t.originalName)}”';
    }
    return '${tracks.length} songs';
  }

  Future<void> _newPlaylist() async {
    if (_busy) return;
    final id = await showNewPlaylistSheet(context, addTrackIds: _ids);
    if (id == null || !mounted) return;
    final playlists = ref.read(playlistsProvider).value ?? const [];
    final name = playlists.where((p) => p.id == id).firstOrNull?.name;
    Navigator.of(context).pop(name ?? 'the new playlist');
  }

  Future<void> _pick(PlaylistView playlist) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ids = await _chooseIds(playlist);
      if (ids == null || !mounted) return;
      try {
        await ref.read(playlistRepositoryProvider).addTracks(playlist.id, ids);
      } on Object catch (e) {
        await _showError(e);
        return;
      }
      if (mounted) Navigator.of(context).pop(playlist.name);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The ids to add to [playlist] after asking about duplicates; null when
  /// the user backed out. Repeats inside the selection itself are not
  /// duplicates.
  Future<List<int>?> _chooseIds(PlaylistView playlist) async {
    final have = {for (final i in playlist.items) i.track.id};
    final selected = _ids;
    final distinct = selected.toSet();
    final already = distinct.where(have.contains).length;
    if (already == 0) return selected;

    if (distinct.length == 1) {
      final t = widget.tracks.first;
      final choice = await _ask(
        message:
            '“${displayTitle(t.title, t.originalName)}” is already in '
            '“${playlist.name}”.',
        actions: [
          ('Don\'t Add', _Duplicates.cancel),
          ('Add Anyway', _Duplicates.all),
        ],
      );
      return choice == _Duplicates.all ? selected : null;
    }
    final choice = await _ask(
      message:
          '$already of these songs ${already == 1 ? 'is' : 'are'} already '
          'in “${playlist.name}”.',
      actions: [
        ('Cancel', _Duplicates.cancel),
        if (already < distinct.length) ('Add New Ones', _Duplicates.onlyNew),
        ('Add All', _Duplicates.all),
      ],
    );
    return switch (choice) {
      _Duplicates.all => selected,
      _Duplicates.onlyNew => [
        for (final id in selected)
          if (!have.contains(id)) id,
      ],
      _ => null,
    };
  }

  Future<_Duplicates?> _ask({
    required String message,
    required List<(String, _Duplicates)> actions,
  }) => showAdaptiveDialog<_Duplicates>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: const Text('Already added'),
      content: Text(message),
      actions: [
        for (final (label, value) in actions)
          DialogAction(
            label: label,
            onPressed: () => Navigator.pop(context, value),
          ),
      ],
    ),
  );

  Future<void> _showError(Object error) => showAdaptiveDialog<void>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: const Text("Couldn't add the songs"),
      content: SelectableText('$error'),
      actions: [
        DialogAction(label: 'OK', onPressed: () => Navigator.pop(context)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    return Material(
      color: c.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          top: 10,
          bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: c.faint,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('add-to-playlist-cancel'),
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: c.accent,
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 17),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Add to Playlist',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 72),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _PlaylistRow(
                    key: const Key('add-to-playlist-new'),
                    leading: Container(
                      width: _artSize,
                      height: _artSize,
                      decoration: BoxDecoration(
                        color: c.fill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(CupertinoIcons.plus, color: c.accent),
                    ),
                    title: 'New Playlist…',
                    accent: true,
                    onTap: _newPlaylist,
                  ),
                  for (final p in playlists)
                    _PlaylistRow(
                      key: Key('add-to-playlist-${p.id}'),
                      leading: PlaylistArtwork(playlist: p, size: _artSize),
                      title: p.name,
                      subtitle: p.meta,
                      onTap: () => _pick(p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _artSize = 56.0;

/// A 72pt row of the sheet (`.plrow`): 56pt artwork, name, optional meta.
class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    super.key,
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.accent = false,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final subtitle = this.subtitle;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: accent ? c.accent : c.text,
                          ),
                        ),
                        if (subtitle != null)
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
            Positioned(
              left: 68,
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
