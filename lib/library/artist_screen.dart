import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/albums_screen.dart';
import 'package:owntune/library/artists_screen.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/songs_screen.dart';
import 'package:owntune/player/player_controller.dart';

/// Number of songs shown on the artist screen before "See All".
const _previewCount = 5;

/// Song rows on artist screens show only the album as subtitle.
String _albumLine(Track t) => t.album?.trim() ?? '';

/// Artist detail (mockup 09): avatar, name, counts, Play/Shuffle, the
/// artist's albums and the first songs.
class ArtistScreen extends StatelessWidget {
  const ArtistScreen({
    super.key,
    required this.artistKey,
    required this.backLabel,
  });

  final String artistKey;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavRow(backLabel: backLabel),
          Expanded(
            child: LiveDetail<Artist>(
              resolve: (library) => library.artist(artistKey),
              builder: (context, artist) => _ArtistBody(artist: artist),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistBody extends ConsumerWidget {
  const _ArtistBody({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final preview = artist.songs.take(_previewCount).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        Center(child: ArtistAvatar(artist: artist, size: 150)),
        const SizedBox(height: 16),
        Text(
          artist.name,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          artistCounts(artist),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: c.muted),
        ),
        const SizedBox(height: 16),
        PlayShuffleButtons(
          onPlay: () => ref
              .read(playerProvider.notifier)
              .playList(artist.songs, start: 0, source: artist.name),
        ),
        if (artist.albums.isNotEmpty) ...[
          const _SectionTitle(title: 'Albums'),
          SizedBox(
            height: AlbumCard.heightFor(150, MediaQuery.textScalerOf(context)),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: artist.albums.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final album = artist.albums[i];
                return AlbumCard(
                  album: album,
                  subtitle: album.year?.toString() ?? '',
                  width: 150,
                  onTap: () =>
                      openAlbum(context, album.key, backLabel: artist.name),
                );
              },
            ),
          ),
        ],
        _SectionTitle(
          title: 'Songs',
          action: artist.songs.length > _previewCount
              ? _SeeAll(
                  onTap: () => openArtistSongs(
                    context,
                    artist.key,
                    backLabel: artist.name,
                  ),
                )
              : null,
        ),
        for (final (i, t) in preview.indexed)
          SongRow(
            // The preview is the start of artist.songs; queue all of them.
            onTap: () => ref
                .read(playerProvider.notifier)
                .playList(artist.songs, start: i, source: artist.name),
            track: t,
            scope: SongMenuScope(
              backLabel: artist.name,
              currentArtist: artist.key,
            ),
            subtitle: _albumLine(t),
            divider: i + 1 < preview.length,
          ),
      ],
    );
  }
}

/// `.h-section`: 22pt title with an optional link on the right.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Text('See All', style: TextStyle(fontSize: 17, color: c.accent)),
      ),
    );
  }
}

/// All songs of an artist ("See All"), titled with the artist's name.
class ArtistSongsScreen extends ConsumerWidget {
  const ArtistSongsScreen({
    super.key,
    required this.artistKey,
    required this.backLabel,
  });

  final String artistKey;
  final String backLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavRow(backLabel: backLabel),
          Expanded(
            child: LiveDetail<Artist>(
              resolve: (library) => library.artist(artistKey),
              builder: (context, artist) => ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  MediaQuery.paddingOf(context).bottom + 16,
                ),
                itemCount: artist.songs.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        artist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.68,
                          color: c.text,
                        ),
                      ),
                    );
                  }
                  final t = artist.songs[i - 1];
                  return SongRow(
                    onTap: () => ref
                        .read(playerProvider.notifier)
                        .playList(
                          artist.songs,
                          start: i - 1,
                          source: artist.name,
                        ),
                    track: t,
                    scope: SongMenuScope(
                      backLabel: artist.name,
                      currentArtist: artist.key,
                    ),
                    subtitle: _albumLine(t),
                    divider: i < artist.songs.length,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
