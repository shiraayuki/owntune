import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/library/artists_screen.dart' show LinkRow;
import 'package:owntune/library/search_screen.dart';
import 'package:owntune/library/songs_screen.dart' show LoadError;
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/playlists/liked_songs.dart';
import 'package:owntune/playlists/new_playlist_sheet.dart';
import 'package:owntune/playlists/playlist_artwork.dart';
import 'package:owntune/playlists/playlist_screen.dart';
import 'package:owntune/playlists/playlist_view.dart';

/// The Playlists tab (mockup 11): search field, the "New Playlist" row, the
/// "Liked Songs" row and one row per playlist, newest first.
class PlaylistsTab extends ConsumerStatefulWidget {
  const PlaylistsTab({super.key});

  @override
  ConsumerState<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends ConsumerState<PlaylistsTab> {
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(playlistsProvider);
    if (async.hasError) {
      return LoadError(
        title: 'Could not load your playlists',
        message: '${async.error}',
      );
    }
    final all = async.value;
    if (all == null) return const SizedBox.shrink();
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final q = foldKey(_query.text);
    final shown = q.isEmpty
        ? all
        : [
            for (final p in all)
              if (foldKey(p.name).contains(q)) p,
          ];
    final liked = ref.watch(likedSongsProvider).value ?? const [];
    final showLiked = q.isEmpty || foldKey('Liked Songs').contains(q);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabSearchField(label: 'Search Playlists', controller: _query),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.paddingOf(context).bottom + 16,
            ),
            children: [
              _NewPlaylistRow(onTap: () => showNewPlaylistSheet(context)),
              if (showLiked)
                LinkRow(
                  key: const Key('playlists-liked'),
                  leading: const LikedArtwork(size: 56),
                  title: 'Liked Songs',
                  subtitle: formatSongsMeta(
                    liked.length,
                    liked.fold<int>(0, (sum, t) => sum + t.durationMs),
                  ),
                  divider: all.isNotEmpty && shown.isNotEmpty,
                  dividerInset: 68,
                  onTap: () => openLikedSongs(context),
                ),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
                  child: Text(
                    'Create a playlist, or add songs with Add to Playlist.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, color: c.muted),
                  ),
                )
              else if (shown.isEmpty && !showLiked)
                NoResults(query: _query.text)
              else
                for (final (i, p) in shown.indexed)
                  LinkRow(
                    leading: PlaylistArtwork(playlist: p, size: 56),
                    title: p.name,
                    subtitle: p.meta,
                    divider: i + 1 < shown.length,
                    dividerInset: 68,
                    onTap: () => openPlaylist(context, p.id),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "New Playlist": an accent plus tile and an accent label (`.plrow.new`).
class _NewPlaylistRow extends StatelessWidget {
  const _NewPlaylistRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return GestureDetector(
      key: const Key('new-playlist-row'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: c.fill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(CupertinoIcons.plus, size: 24, color: c.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'New Playlist',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.accent,
                      ),
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
