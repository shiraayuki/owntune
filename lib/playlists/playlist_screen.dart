import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/library/album_screen.dart' show PlayShuffleButtons;
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/songs_screen.dart';
import 'package:owntune/player/mini_player.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/playlists/edit_playlist_screen.dart';
import 'package:owntune/playlists/playlist_artwork.dart';
import 'package:owntune/playlists/playlist_view.dart';

/// Opens the playlist page above the tab shell.
Future<void> openPlaylist(BuildContext context, int playlistId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistScreen(playlistId: playlistId),
      ),
    );

/// Playlist detail (mockup 12): cover, name, meta, Play/Shuffle and the
/// songs in playlist order. The page pops itself when the playlist is gone.
class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  var _popping = false;

  PlaylistView? _view() {
    final all = ref.read(playlistsProvider).value;
    if (all == null) return null;
    for (final p in all) {
      if (p.id == widget.playlistId) return p;
    }
    return null;
  }

  void _popWhenGone() {
    if (_popping) return;
    _popping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null) return;
      // Remove this screen even if another one is on top of it.
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else if (route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  Future<void> _delete(PlaylistView view) async {
    final repo = ref.read(playlistRepositoryProvider);
    final navigator = Navigator.of(context);
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text('Delete "${view.name}"?'),
        content: const Text('The songs stay in your library.'),
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
      // The page pops itself once the playlist is gone.
      await repo.delete(view.id);
    } catch (e) {
      if (!navigator.mounted) return;
      await showAdaptiveDialog<void>(
        context: navigator.context,
        builder: (context) => AlertDialog.adaptive(
          title: Text('Could not delete "${view.name}"'),
          content: SelectableText('$e'),
          actions: [
            DialogAction(label: 'OK', onPressed: () => Navigator.pop(context)),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(playlistsProvider);
    PlaylistView? view;
    for (final p in async.value ?? const <PlaylistView>[]) {
      if (p.id == widget.playlistId) view = p;
    }
    if (view == null && async.hasValue) _popWhenGone();

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const MiniPlayer(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavRow(
            backLabel: 'Playlists',
            trailing: DetailMoreButton(
              items: [
                DetailMenuItem(
                  key: const Key('menu-edit-playlist'),
                  label: 'Edit Playlist',
                  icon: CupertinoIcons.pencil,
                  onTap: () {
                    final current = _view();
                    if (current != null) openEditPlaylist(context, current);
                  },
                ),
                DetailMenuItem(
                  key: const Key('menu-delete-playlist'),
                  label: 'Delete Playlist',
                  icon: CupertinoIcons.trash,
                  destructive: true,
                  onTap: () {
                    final current = _view();
                    if (current != null) _delete(current);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: view == null
                ? const SizedBox.shrink()
                : _PlaylistBody(playlist: view),
          ),
        ],
      ),
    );
  }
}

class _PlaylistBody extends ConsumerWidget {
  const _PlaylistBody({required this.playlist});

  final PlaylistView playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final player = ref.read(playerProvider.notifier);
    final items = playlist.items;
    final name = playlist.name;
    final empty = items.isEmpty;

    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.18),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: PlaylistArtwork(
                playlist: playlist,
                size: math.min(270, constraints.maxWidth - 32),
                radius: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            playlist.meta,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
          const SizedBox(height: 16),
          PlayShuffleButtons(
            onPlay: empty
                ? null
                : () => player.playList(
                    playlist.tracks,
                    start: 0,
                    source: name,
                    shuffle: false,
                  ),
            onShuffle: empty
                ? null
                : () => player.playList(
                    playlist.tracks,
                    start: 0,
                    source: name,
                    shuffle: true,
                  ),
          ),
          const SizedBox(height: 6),
          if (empty)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
              child: Text(
                'This playlist is empty. Add songs with Add to Playlist.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, color: c.muted),
              ),
            )
          else
            for (final (i, item) in items.indexed)
              SongRow(
                key: ValueKey(item.entryId),
                track: item.track,
                scope: SongMenuScope(
                  backLabel: name,
                  playlistEntry: (
                    playlistId: playlist.id,
                    entryId: item.entryId,
                  ),
                ),
                divider: i + 1 < items.length,
                onTap: () =>
                    player.playList(playlist.tracks, start: i, source: name),
              ),
        ],
      ),
    );
  }
}
