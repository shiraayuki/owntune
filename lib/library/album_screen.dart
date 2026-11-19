import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/songs_screen.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/mini_player.dart';
import 'package:owntune/player/player_controller.dart';

/// Album detail (mockup 07): cover, title, artist, meta, Play/Shuffle and
/// the tracks by disc and number.
class AlbumScreen extends StatelessWidget {
  const AlbumScreen({
    super.key,
    required this.albumKey,
    required this.backLabel,
  });

  final AlbumKey albumKey;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const MiniPlayer(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavRow(backLabel: backLabel),
          Expanded(
            child: LiveDetail<Album>(
              resolve: (library) => library.album(albumKey),
              builder: (context, album) => _AlbumBody(album: album),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumBody extends ConsumerWidget {
  const _AlbumBody({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final storage = ref.watch(storageProvider);
    final cover = album.coverFile;
    final meta = [
      if (album.genre != null) album.genre!,
      if (album.year != null) '${album.year}',
    ].join(' · ');
    final albumArtist = artistGroupKey(album.artist);

    final rows = <Widget>[];
    int? disc;
    for (final (i, t) in album.tracks.indexed) {
      if (album.hasMultipleDiscs && (i == 0 || t.discNumber != disc)) {
        rows.add(_DiscHeader(disc: t.discNumber));
      }
      disc = t.discNumber;
      final last = i + 1 == album.tracks.length;
      final nextDisc = last ? null : album.tracks[i + 1].discNumber;
      rows.add(
        AlbumTrackRow(
          onTap: () => ref
              .read(playerProvider.notifier)
              .playList(album.tracks, start: i, source: album.title),
          track: t,
          scope: SongMenuScope(backLabel: album.title, currentAlbum: album.key),
          showArtist: artistGroupKey(t.artist) != albumArtist,
          divider: !last && !(album.hasMultipleDiscs && nextDisc != disc),
        ),
      );
    }

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
              child: Artwork(
                file: cover == null ? null : storage.coverFile(cover),
                size: math.min(270, constraints.maxWidth - 32),
                radius: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            album.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            album.artist,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, color: c.accent),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ],
          const SizedBox(height: 16),
          PlayShuffleButtons(
            onPlay: () => ref
                .read(playerProvider.notifier)
                .playList(
                  album.tracks,
                  start: 0,
                  source: album.title,
                  shuffle: false,
                ),
            onShuffle: () => ref
                .read(playerProvider.notifier)
                .playList(
                  album.tracks,
                  start: 0,
                  source: album.title,
                  shuffle: true,
                ),
          ),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }
}

/// Play (from the first song, shuffle off) and Shuffle (shuffle on).
class PlayShuffleButtons extends StatelessWidget {
  const PlayShuffleButtons({
    super.key,
    required this.onPlay,
    required this.onShuffle,
  });

  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: PillButton(
          label: 'Play',
          icon: CupertinoIcons.play_fill,
          secondary: true,
          expand: true,
          onPressed: onPlay,
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: PillButton(
          label: 'Shuffle',
          icon: CupertinoIcons.shuffle,
          secondary: true,
          expand: true,
          onPressed: onShuffle,
        ),
      ),
    ],
  );
}

class _DiscHeader extends StatelessWidget {
  const _DiscHeader({required this.disc});

  final int? disc;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(
        disc == null ? 'No Disc' : 'Disc $disc',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: c.muted,
        ),
      ),
    );
  }
}

/// 48pt track row (`.row.track`): number, title (and artist if it differs
/// from the album artist), duration.
class AlbumTrackRow extends ConsumerWidget {
  const AlbumTrackRow({
    super.key,
    required this.track,
    required this.scope,
    required this.showArtist,
    this.divider = true,
    this.onTap,
  });

  final Track track;
  final SongMenuScope scope;
  final bool showArtist;
  final bool divider;

  /// Plays the album from this track.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final playing = ref.watch(
      currentTrackProvider.select((t) => t?.id == track.id),
    );
    final muted = TextStyle(
      fontSize: 15,
      color: c.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: playing
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: Icon(
                            CupertinoIcons.chart_bar_alt_fill,
                            size: 18,
                            color: c.accent,
                          ),
                        )
                      : Text(
                          track.trackNumber?.toString() ?? '',
                          textAlign: TextAlign.right,
                          style: muted,
                        ),
                ),
                const SizedBox(width: 14),
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
                          color: playing ? c.accent : c.text,
                        ),
                      ),
                      if (showArtist)
                        Text(
                          displayArtist(track.artist),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, color: c.muted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Text(formatDuration(track.durationMs), style: muted),
              ],
            ),
          ),
          if (divider)
            Positioned(
              left: 36,
              right: 0,
              bottom: 0,
              child: Container(height: 0.5, color: c.line),
            ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPressStart: (details) =>
          showSongMenu(context, ref, track, details.globalPosition, scope),
      child: row,
    );
  }
}
