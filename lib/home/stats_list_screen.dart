import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart' show Track;
import 'package:owntune/home/home_cards.dart' show homeBackLabel;
import 'package:owntune/home/stats_providers.dart';
import 'package:owntune/home/stats_rankings.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/songs_screen.dart' show LoadError;
import 'package:owntune/player/mini_player.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/queue_source.dart';

const _tabular = [FontFeature.tabularFigures()];

/// The rankings that have a full-list page behind their "See All".
enum StatsList {
  songs('Top Songs'),
  artists('Top Artists'),
  albums('Top Albums');

  const StatsList(this.title);

  final String title;
}

/// Opens the full ranking above the tab shell.
Future<void> openStatsList(BuildContext context, StatsList list) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => StatsListScreen(list: list)),
    );

/// What a tap on row [index] of [rows] does: a song plays the songs of the
/// list from it (queue source [songsSource]), an artist or album opens its
/// page with [backLabel] ("Home" on the Stats page, the list title on a full
/// list).
void tapRankRow(
  BuildContext context,
  WidgetRef ref,
  List<RankRow> rows,
  int index, {
  required String songsSource,
  required String backLabel,
}) {
  switch (rows[index].target) {
    case SongTarget():
      final tracks = <Track>[];
      var start = 0;
      for (var i = 0; i < rows.length; i++) {
        final target = rows[i].target;
        if (target is! SongTarget) continue;
        if (i == index) start = tracks.length;
        tracks.add(target.track);
      }
      ref
          .read(playerProvider.notifier)
          .playList(
            tracks,
            start: start,
            source: QueueSource(QueueSourceKind.other, songsSource),
          );
    case ArtistTarget(:final artist):
      openArtist(context, artist.key, backLabel: backLabel);
    case AlbumTarget(:final album):
      openAlbum(context, album.key, backLabel: backLabel);
  }
}

/// A ranking in full (up to [topListLimit] rows). It follows [statsProvider],
/// so it keeps the period chosen on the Stats page.
class StatsListScreen extends ConsumerStatefulWidget {
  const StatsListScreen({super.key, required this.list});

  final StatsList list;

  @override
  ConsumerState<StatsListScreen> createState() => _StatsListScreenState();
}

class _StatsListScreenState extends ConsumerState<StatsListScreen> {
  // The last page, shown while Stats loads again (a new day, a new period),
  // so the list does not flash empty.
  StatsView? _last;

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final state = ref.watch(statsProvider);
    final view = state.value ?? _last;
    _last = view;
    final tops = view?.tops;
    final rows = tops == null
        ? const <RankRow>[]
        : switch (list) {
            StatsList.songs => tops.songs,
            StatsList.artists => tops.artists,
            StatsList.albums => tops.albums,
          };
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
            child: state.hasError && !state.hasValue
                ? LoadError(
                    title: 'Could not load Stats',
                    message: state.error.toString(),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => RankRowTile(
                      key: Key('stats-list-$i'),
                      rank: i + 1,
                      row: rows[i],
                      round: list == StatsList.artists,
                      onTap: () => tapRankRow(
                        context,
                        ref,
                        rows,
                        i,
                        songsSource: 'Top Songs',
                        backLabel: list.title,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One ranking row (rank, cover, title, plays meter and count); [onTap] plays
/// or opens what it stands for.
class RankRowTile extends ConsumerWidget {
  const RankRowTile({
    super.key,
    required this.rank,
    required this.row,
    required this.round,
    required this.onTap,
  });

  final int rank;
  final RankRow row;
  final bool round;
  final VoidCallback onTap;

  String? get _cover => switch (row.target) {
    SongTarget(:final track) => track.coverFile,
    ArtistTarget(:final artist) => artist.avatarCover,
    AlbumTarget(:final album) => album.coverFile,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final cover = _cover;
    final count = row.playsLabel.split(' ');
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    color: c.muted,
                    fontFeatures: _tabular,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Artwork(
                file: cover == null
                    ? null
                    : ref.watch(storageProvider).coverFile(cover),
                size: 40,
                radius: round ? 20 : 6,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                    if (row.subtitle.isNotEmpty)
                      Text(
                        row.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Container(
                        height: 4,
                        color: c.fill,
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: row.meter.clamp(0.0, 1.0),
                          child: ColoredBox(
                            color: c.accent,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    count.first,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                      fontFeatures: _tabular,
                    ),
                  ),
                  Text(
                    count.last,
                    style: TextStyle(fontSize: 13, height: 1.2, color: c.muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
