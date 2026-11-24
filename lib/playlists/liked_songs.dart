import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/album_screen.dart' show PlayShuffleButtons;
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/songs_screen.dart';
import 'package:owntune/player/mini_player.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/queue_source.dart';
import 'package:owntune/playlists/playlist_view.dart';

/// The liked songs, most recently liked first (ties: higher id first).
final likedSongsProvider = Provider<AsyncValue<List<Track>>>(
  (ref) => ref.watch(tracksProvider).whenData((tracks) {
    final liked = [
      for (final t in tracks)
        if (t.likedAt != null) t,
    ];
    liked.sort((a, b) {
      final byTime = b.likedAt!.compareTo(a.likedAt!);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return liked;
  }),
);

/// The heart tile of Liked Songs (`.art.liked`): an accent square with a
/// heart.
class LikedArtwork extends StatelessWidget {
  const LikedArtwork({super.key, required this.size, this.radius = 8});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.heart_fill,
        size: size * 0.43,
        color: c.accentText,
      ),
    );
  }
}

/// Opens the Liked Songs page above the tab shell.
Future<void> openLikedSongs(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const LikedSongsScreen()));

/// The Liked Songs page: heart tile, meta, Play/Shuffle and the songs, newest
/// like first. It has no "…" menu; songs leave it by being unliked.
class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});

  static const _source = QueueSource.liked();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final player = ref.read(playerProvider.notifier);
    final songs = ref.watch(likedSongsProvider).value ?? const <Track>[];
    final empty = songs.isEmpty;
    final durationMs = songs.fold<int>(0, (sum, t) => sum + t.durationMs);

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const MiniPlayer(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NavRow(backLabel: 'Playlists'),
          Expanded(
            child: LayoutBuilder(
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
                      child: LikedArtwork(
                        size: math.min(270, constraints.maxWidth - 32),
                        radius: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Liked Songs',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatSongsMeta(songs.length, durationMs),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                  const SizedBox(height: 16),
                  PlayShuffleButtons(
                    onPlay: empty
                        ? null
                        : () => player.playList(
                            songs,
                            start: 0,
                            source: _source,
                            shuffle: false,
                          ),
                    onShuffle: empty
                        ? null
                        : () => player.playList(
                            songs,
                            start: 0,
                            source: _source,
                            shuffle: true,
                          ),
                  ),
                  const SizedBox(height: 6),
                  if (empty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
                      child: Text(
                        'Songs you like appear here. '
                        'Tap ♥ in the player to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 17, color: c.muted),
                      ),
                    )
                  else
                    for (final (i, song) in songs.indexed)
                      SongRow(
                        key: ValueKey(song.id),
                        track: song,
                        scope: const SongMenuScope(backLabel: 'Liked Songs'),
                        divider: i + 1 < songs.length,
                        onTap: () =>
                            player.playList(songs, start: i, source: _source),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
