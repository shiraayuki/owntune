import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/home/for_you.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/songs_screen.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/playlists/liked_songs.dart';
import 'package:owntune/playlists/playlist_artwork.dart';

/// Where the song menu and the pages opened from Home lead back to.
const homeBackLabel = 'Home';

/// The menu scope of songs on Home.
const homeSongScope = SongMenuScope(backLabel: homeBackLabel);

/// A shortcut tile (`.tile`): 56 pt high, artwork on the left, title in up to
/// two lines.
class HomeTileCard extends ConsumerWidget {
  const HomeTileCard({super.key, required this.tile, required this.onTap});

  static const height = 56.0;

  final HomeTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final storage = ref.watch(storageProvider);
    Widget cover(String? name, {double radius = 0}) => Artwork(
      file: name == null ? null : storage.coverFile(name),
      size: height,
      radius: radius,
    );
    final art = switch (tile) {
      AlbumTile(:final album) => cover(album.coverFile),
      ArtistTile(:final artist) => cover(
        artist.avatarCover,
        radius: height / 2,
      ),
      PlaylistTile(:final playlist) => PlaylistArtwork(
        playlist: playlist,
        size: height,
        radius: 0,
      ),
      LikedTile() => const LikedArtwork(size: height, radius: 0),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.fill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            art,
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  tile.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Title of a section with the "›" that opens its full list (`.home-h`).
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({super.key, required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 18, color: c.muted),
          ],
        ),
      ),
    );
  }
}

/// The card width of a horizontal row (`.hcard`).
const homeCardWidth = 132.0;

/// Height of a row of cards at [scaler]: cover, 6 pt gap and two text lines.
double homeRowHeight(TextScaler scaler) =>
    homeCardWidth +
    6 +
    (scaler.scale(14) * 1.25).ceilToDouble() +
    (scaler.scale(13) * 1.25).ceilToDouble();

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final GestureLongPressStartCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPressStart: onLongPress,
      child: SizedBox(
        width: homeCardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            art,
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, height: 1.25, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A song in a row: tap plays [onTap], long-press opens the song menu.
class HomeSongCard extends ConsumerWidget {
  const HomeSongCard({super.key, required this.card, required this.onTap});

  final SongCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = card.track;
    final cover = track.coverFile;
    return _HomeCard(
      art: Artwork(
        file: cover == null
            ? null
            : ref.watch(storageProvider).coverFile(cover),
        size: homeCardWidth,
        radius: 8,
      ),
      title: displayTitle(track.title, track.originalName),
      subtitle: card.subtitle,
      onTap: onTap,
      onLongPress: (details) => showSongMenu(
        context,
        ref,
        track,
        details.globalPosition,
        homeSongScope,
      ),
    );
  }
}

/// An album in a row; tap opens it.
class HomeAlbumCard extends ConsumerWidget {
  const HomeAlbumCard({super.key, required this.album, required this.onTap});

  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = album.coverFile;
    return _HomeCard(
      art: Artwork(
        file: cover == null
            ? null
            : ref.watch(storageProvider).coverFile(cover),
        size: homeCardWidth,
        radius: 8,
      ),
      title: album.title,
      subtitle: album.artist,
      onTap: onTap,
    );
  }
}
