import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/download/search_online_screen.dart';
import 'package:owntune/home/for_you.dart';
import 'package:owntune/home/home_cards.dart';
import 'package:owntune/home/home_list_screen.dart';
import 'package:owntune/home/home_providers.dart';
import 'package:owntune/import/import_controller.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/songs_screen.dart' show LoadError;
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/queue_source.dart';
import 'package:owntune/playlists/liked_songs.dart';
import 'package:owntune/playlists/playlist_screen.dart';

/// The For You sub-tab: the empty state while the library has no songs, the
/// sections otherwise.
class ForYouScreen extends ConsumerWidget {
  const ForYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    if (library.value?.tracks.isEmpty ?? false) {
      return const HomeEmptyState(key: Key('for-you-empty'));
    }
    return ref
        .watch(forYouProvider)
        .when(
          data: (forYou) => _Sections(forYou: forYou),
          error: (e, _) =>
              LoadError(title: 'Could not load Home', message: e.toString()),
          loading: () => const SizedBox.shrink(),
        );
  }
}

/// Tiles and the rows of cards (mockups 01 and 02; the continue card and
/// the shuffle buttons were dropped as clutter). Sections without items are
/// left out.
class _Sections extends ConsumerWidget {
  const _Sections({required this.forYou});

  final ForYou forYou;

  void _openTile(BuildContext context, HomeTile tile) {
    switch (tile) {
      case AlbumTile(:final album):
        openAlbum(context, album.key, backLabel: homeBackLabel);
      case ArtistTile(:final artist):
        openArtist(context, artist.key, backLabel: homeBackLabel);
      case PlaylistTile(:final playlist):
        openPlaylist(context, playlist.id, backLabel: homeBackLabel);
      case LikedTile():
        openLikedSongs(context, backLabel: homeBackLabel);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider.notifier);
    final rowHeight = homeRowHeight(MediaQuery.textScalerOf(context));

    Widget songRow(String suffix, HomeList list, List<SongCard> cards) {
      final title = list.title;
      final shown = cards.take(homeRowLimit).toList();
      final source = QueueSource(QueueSourceKind.other, title);
      return _Row(
        suffix: suffix,
        list: list,
        height: rowHeight,
        count: shown.length,
        itemBuilder: (context, i) => HomeSongCard(
          key: Key('home-card-$suffix-${shown[i].track.id}'),
          card: shown[i],
          onTap: () => player.playList(
            [for (final c in shown) c.track],
            start: i,
            source: source,
          ),
        ),
      );
    }

    final albums = forYou.recentlyAdded.take(homeRowLimit).toList();
    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        if (forYou.tiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _TileGrid(
              tiles: forYou.tiles,
              onTap: (tile) => _openTile(context, tile),
            ),
          ),
        if (forYou.onRepeat.isNotEmpty)
          songRow('on-repeat', HomeList.onRepeat, forYou.onRepeat),
        if (albums.isNotEmpty)
          _Row(
            suffix: 'recently-added',
            list: HomeList.recentlyAdded,
            height: rowHeight,
            count: albums.length,
            itemBuilder: (context, i) => HomeAlbumCard(
              key: Key('home-card-recently-added-$i'),
              album: albums[i],
              onTap: () =>
                  openAlbum(context, albums[i].key, backLabel: homeBackLabel),
            ),
          ),
        if (forYou.rediscover.isNotEmpty)
          songRow('rediscover', HomeList.rediscover, forYou.rediscover),
        if (forYou.neverPlayed.isNotEmpty)
          songRow('never-played', HomeList.neverPlayed, forYou.neverPlayed),
      ],
    );
  }
}

/// Up to three rows of two tiles.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles, required this.onTap});

  final List<HomeTile> tiles;
  final ValueChanged<HomeTile> onTap;

  @override
  Widget build(BuildContext context) {
    Widget tile(int i) => i < tiles.length
        ? HomeTileCard(
            key: Key('home-tile-$i'),
            tile: tiles[i],
            onTap: () => onTap(tiles[i]),
          )
        : const SizedBox.shrink();
    return Column(
      children: [
        for (var row = 0; row * 2 < tiles.length; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          SizedBox(
            height: HomeTileCard.height,
            child: Row(
              children: [
                Expanded(child: tile(row * 2)),
                const SizedBox(width: 8),
                Expanded(child: tile(row * 2 + 1)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A header and a horizontal row of cards.
class _Row extends StatelessWidget {
  const _Row({
    required this.suffix,
    required this.list,
    required this.height,
    required this.count,
    required this.itemBuilder,
  });

  final String suffix;
  final HomeList list;
  final double height;
  final int count;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HomeSectionHeader(
        key: Key('home-header-$suffix'),
        title: list.title,
        onTap: () => openHomeList(context, list),
      ),
      SizedBox(
        height: height,
        child: ListView.separated(
          key: Key('home-row-$suffix'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: itemBuilder,
        ),
      ),
    ],
  );
}

/// Mockup 05: glyph, headline, text and two full-width buttons. Shared by the
/// For You and Stats sub-tabs.
class HomeEmptyState extends ConsumerWidget {
  const HomeEmptyState({super.key});

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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(CupertinoIcons.music_note_2, size: 64, color: c.faint),
                  const SizedBox(height: 20),
                  Text(
                    'Your music lives here',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Import files you already have, or find songs on '
                    'YouTube.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, color: c.muted),
                  ),
                  const SizedBox(height: 24),
                  PillButton(
                    icon: CupertinoIcons.square_arrow_down,
                    label: 'Import Music',
                    expand: true,
                    onPressed: running
                        ? null
                        : () => ref
                              .read(importControllerProvider.notifier)
                              .pickAndImport(),
                  ),
                  const SizedBox(height: 12),
                  PillButton(
                    icon: CupertinoIcons.globe,
                    label: 'Search Online',
                    secondary: true,
                    expand: true,
                    onPressed: () =>
                        openSearchOnline(context, backLabel: 'Home'),
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
