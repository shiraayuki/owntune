import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/home/for_you.dart';
import 'package:owntune/home/home_cards.dart';
import 'package:owntune/home/home_providers.dart';
import 'package:owntune/library/artists_screen.dart' show LinkRow;
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/library.dart' show Album;
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/songs_screen.dart';
import 'package:owntune/player/mini_player.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/queue_source.dart';

/// The sections of For You that have a full-list page behind their "›".
enum HomeList {
  onRepeat('On Repeat'),
  recentlyAdded('Recently Added'),
  rediscover('Rediscover'),
  neverPlayed('Never Played');

  const HomeList(this.title);

  final String title;
}

/// Opens the full list of a Home section above the tab shell.
Future<void> openHomeList(BuildContext context, HomeList list) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => HomeListScreen(list: list)));

/// A Home section in full (up to [homeListLimit] items): songs play the list
/// from the tapped one, albums open. It follows [forYouProvider].
class HomeListScreen extends ConsumerWidget {
  const HomeListScreen({super.key, required this.list});

  final HomeList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final state = ref.watch(forYouProvider);
    final forYou = state.value;
    final bottom = MediaQuery.paddingOf(context).bottom + 16;
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const MiniPlayer(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NavRow(backLabel: homeBackLabel),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              list.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.68,
                color: c.text,
              ),
            ),
          ),
          Expanded(
            child: switch ((list, forYou)) {
              (_, null) when state.hasError => LoadError(
                title: 'Could not load Home',
                message: state.error.toString(),
              ),
              (_, null) => const SizedBox.shrink(),
              (HomeList.recentlyAdded, final f?) => _AlbumList(
                albums: f.recentlyAdded,
                title: list.title,
                bottom: bottom,
              ),
              (_, final f?) => _SongList(
                cards: switch (list) {
                  HomeList.onRepeat => f.onRepeat,
                  HomeList.rediscover => f.rediscover,
                  _ => f.neverPlayed,
                },
                title: list.title,
                bottom: bottom,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _SongList extends ConsumerWidget {
  const _SongList({
    required this.cards,
    required this.title,
    required this.bottom,
  });

  final List<SongCard> cards;
  final String title;
  final double bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider.notifier);
    final source = QueueSource(QueueSourceKind.other, title);
    final tracks = [for (final c in cards) c.track];
    final scope = SongMenuScope(backLabel: title);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
      itemCount: cards.length,
      itemBuilder: (context, i) => SongRow(
        key: Key('home-list-song-${cards[i].track.id}'),
        track: cards[i].track,
        scope: scope,
        subtitle: cards[i].subtitle,
        divider: i + 1 < cards.length,
        onTap: () => player.playList(tracks, start: i, source: source),
      ),
    );
  }
}

class _AlbumList extends ConsumerWidget {
  const _AlbumList({
    required this.albums,
    required this.title,
    required this.bottom,
  });

  final List<Album> albums;
  final String title;
  final double bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageProvider);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final cover = albums[i].coverFile;
        return LinkRow(
          key: Key('home-list-album-$i'),
          leading: Artwork(
            file: cover == null ? null : storage.coverFile(cover),
            size: 48,
            radius: 6,
          ),
          title: albums[i].title,
          subtitle: albums[i].artist,
          divider: i + 1 < albums.length,
          onTap: () => openAlbum(context, albums[i].key, backLabel: title),
        );
      },
    );
  }
}
