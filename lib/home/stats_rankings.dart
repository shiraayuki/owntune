/// Rankings, genre mix, monthly recap and library overview of the Stats page.
///
/// Pure Dart. The history only holds track ids, so everything is resolved
/// against the current [Library]: renamed artists and albums count under their
/// current name, and deleted songs never rank (they still count as "Unknown"
/// in the genre mix, so its total equals Songs played).
library;

import 'package:owntune/app/format.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/home/stats_period.dart';
import 'package:owntune/home/stats_repository.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/sort_key.dart';

/// What a tap on a [RankRow] opens or plays.
sealed class RankTarget {}

final class SongTarget extends RankTarget {
  SongTarget(this.track);
  final Track track;
}

final class ArtistTarget extends RankTarget {
  ArtistTarget(this.artist);
  final Artist artist;
}

final class AlbumTarget extends RankTarget {
  AlbumTarget(this.album);
  final Album album;
}

/// One row of a ranking.
class RankRow {
  const RankRow({
    required this.target,
    required this.title,
    required this.subtitle,
    required this.plays,
    required this.meter,
  });

  final RankTarget target;
  final String title;
  final String subtitle;
  final int plays;

  /// `plays` relative to the first row of its list, 0..1.
  final double meter;

  String get playsLabel => plays == 1 ? '1 play' : '$plays plays';
}

/// The top songs, artists and albums of a period, at most [topListLimit] each.
class TopLists {
  const TopLists({
    required this.songs,
    required this.artists,
    required this.albums,
  });

  final List<RankRow> songs;
  final List<RankRow> artists;
  final List<RankRow> albums;
}

const topListLimit = 50;

class _Sum {
  _Sum(this.target, this.title, this.subtitle);

  final RankTarget target;
  final String title;
  final String subtitle;
  int plays = 0;
  int listenedMs = 0;
}

List<RankRow> _rank(
  Iterable<_Sum> sums,
  String Function(_Sum) subtitleOf, {
  int limit = topListLimit,
}) {
  final sorted = sums.where((s) => s.plays > 0).toList()
    ..sort((a, b) {
      final byPlays = b.plays.compareTo(a.plays);
      return byPlays != 0 ? byPlays : b.listenedMs.compareTo(a.listenedMs);
    });
  if (sorted.isEmpty) return const [];
  final top = sorted.first.plays;
  return [
    for (final s in sorted.take(limit))
      RankRow(
        target: s.target,
        title: s.title,
        subtitle: subtitleOf(s),
        plays: s.plays,
        meter: s.plays / top,
      ),
  ];
}

RankRow _songRow(Track t, int plays, double meter) => RankRow(
  target: SongTarget(t),
  title: displayTitle(t.title, t.originalName),
  subtitle: displayArtist(t.artist),
  plays: plays,
  meter: meter,
);

Map<int, Track> _byId(Library library) => {
  for (final t in library.tracks) t.id: t,
};

TopLists buildTopLists({
  required Library library,
  required List<TrackTotal> totals,
}) {
  final tracks = _byId(library);
  final songs = <_Sum>[];
  final artists = <String, _Sum>{};
  final albums = <AlbumKey, _Sum>{};
  for (final total in totals) {
    final t = tracks[total.trackId];
    if (t == null || total.plays <= 0) continue;
    songs.add(
      _Sum(
          SongTarget(t),
          displayTitle(t.title, t.originalName),
          displayArtist(t.artist),
        )
        ..plays = total.plays
        ..listenedMs = total.listenedMs,
    );
    final artist = library.artist(artistGroupKey(t.artist));
    if (artist != null) {
      (artists[artist.key] ??= _Sum(ArtistTarget(artist), artist.name, ''))
        ..plays += total.plays
        ..listenedMs += total.listenedMs;
    }
    final key = albumKeyOf(t);
    final album = key == null ? null : library.album(key);
    if (album != null) {
      (albums[key!] ??= _Sum(AlbumTarget(album), album.title, album.artist))
        ..plays += total.plays
        ..listenedMs += total.listenedMs;
    }
  }
  return TopLists(
    songs: _rank(songs, (s) => s.subtitle),
    artists: _rank(artists.values, (s) => formatListening(s.listenedMs)),
    albums: _rank(albums.values, (s) => s.subtitle),
  );
}

/// The genre mix of a period: the top 4 genres and "Other".
class GenreMix {
  const GenreMix({required this.eyebrow, required this.genres});

  final String eyebrow;
  final List<({String name, int percent, int plays})> genres;
}

const _unknownGenre = 'Unknown';
const _otherGenre = 'Other';

/// Counted plays per genre tag, folded case-insensitively. Blank tags and
/// deleted songs are "Unknown". `null` when the period has no plays.
GenreMix? buildGenres({
  required Library library,
  required List<TrackTotal> totals,
  required StatsPeriod period,
}) {
  final tracks = _byId(library);
  // folded key -> total plays, and per spelling plays in first-seen order.
  final plays = <String, int>{};
  final spellings = <String, Map<String, int>>{};
  var all = 0;
  for (final total in totals) {
    if (total.plays <= 0) continue;
    final raw = tracks[total.trackId]?.genre?.trim();
    final spelling = (raw == null || raw.isEmpty) ? _unknownGenre : raw;
    final key = spelling.toLowerCase();
    plays[key] = (plays[key] ?? 0) + total.plays;
    final bySpelling = spellings[key] ??= {};
    bySpelling[spelling] = (bySpelling[spelling] ?? 0) + total.plays;
    all += total.plays;
  }
  if (all == 0) return null;

  String nameOf(String key) {
    String? best;
    var bestPlays = 0;
    spellings[key]!.forEach((spelling, n) {
      if (best == null || n > bestPlays) {
        best = spelling;
        bestPlays = n;
      }
    });
    return best!;
  }

  // Dart maps keep insertion order and sort is stable enough via the index.
  final keys = plays.keys.toList();
  final order = List<int>.generate(keys.length, (i) => i)
    ..sort((a, b) {
      final byPlays = plays[keys[b]]!.compareTo(plays[keys[a]]!);
      return byPlays != 0 ? byPlays : a.compareTo(b);
    });
  final top = order.take(4).toList();
  final shownPlays = [for (final i in top) plays[keys[i]]!];
  final otherPlays = all - shownPlays.fold<int>(0, (a, b) => a + b);
  final percents = largestRemainderPercents([
    ...shownPlays,
    if (otherPlays > 0) otherPlays,
  ]);
  return GenreMix(
    eyebrow:
        'Genre mix · ${all == 1 ? '1 play' : '$all plays'} '
        '${periodPhrase(period)}',
    genres: [
      for (var i = 0; i < top.length; i++)
        (
          name: nameOf(keys[top[i]]),
          percent: percents[i],
          plays: shownPlays[i],
        ),
      if (otherPlays > 0)
        (name: _otherGenre, percent: percents.last, plays: otherPlays),
    ],
  );
}

/// The "Your {Month} so far" card.
class MonthRecap {
  const MonthRecap({
    required this.eyebrow,
    required this.total,
    required this.caption,
    required this.topSong,
    required this.newFinds,
  });

  final String eyebrow;
  final String total;
  final String caption;
  final RankRow? topSong;
  final int newFinds;
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthName(DateTime d) => _monthNames[d.month - 1];

/// The recap of the calendar month of [now]; `null` without listening this
/// month. [previousMonthListenedMs] is `null` when the history does not cover
/// the previous month, which leaves out the comparison.
MonthRecap? buildRecap({
  required DateTime now,
  required Library library,
  required List<TrackTotal> month,
  required int monthListenedMs,
  required int monthDays,
  required int? previousMonthListenedMs,
  required Map<int, ({DateTime first, int counted})> trackHistory,
}) {
  if (monthListenedMs <= 0) return null;

  var caption = 'listened in $monthDays ${monthDays == 1 ? 'day' : 'days'}';
  if (previousMonthListenedMs != null) {
    final previous = _monthName(DateTime(now.year, now.month - 1));
    final diff = monthListenedMs - previousMonthListenedMs;
    caption += sameListening(monthListenedMs, previousMonthListenedMs)
        ? ', same as $previous'
        : ', ${formatListening(diff.abs())} '
              '${diff > 0 ? 'more' : 'less'} than $previous';
  }

  final tracks = _byId(library);
  Track? topTrack;
  TrackTotal? top;
  for (final total in month) {
    final t = tracks[total.trackId];
    if (t == null || total.plays <= 0) continue;
    if (top == null ||
        total.plays > top.plays ||
        (total.plays == top.plays && total.listenedMs > top.listenedMs)) {
      top = total;
      topTrack = t;
    }
  }

  var newFinds = 0;
  for (final t in library.tracks) {
    final h = trackHistory[t.id];
    if (h == null) continue;
    if (h.first.year == now.year &&
        h.first.month == now.month &&
        t.playCount == h.counted) {
      newFinds++;
    }
  }

  return MonthRecap(
    eyebrow: 'Your ${_monthName(now)} so far',
    total: formatListening(monthListenedMs),
    caption: caption,
    topSong: top == null ? null : _songRow(topTrack!, top.plays, 1),
    newFinds: newFinds,
  );
}

/// The "Your Library" card.
class LibraryOverview {
  const LibraryOverview({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.playlists,
    required this.duration,
    required this.storage,
  });

  final int songs;
  final int albums;
  final int artists;
  final int playlists;
  final String duration;

  /// `null` while the storage size is unknown.
  final String? storage;
}

LibraryOverview buildLibraryOverview({
  required Library library,
  required int playlistCount,
  required int? storageBytes,
}) => LibraryOverview(
  songs: library.tracks.length,
  albums: library.albums.length,
  artists: library.artists.length,
  playlists: playlistCount,
  duration: formatListening(
    library.tracks.fold<int>(0, (sum, t) => sum + t.durationMs),
  ),
  storage: storageBytes == null ? null : formatBytes(storageBytes),
);

/// "Most Played of All Time": the top 5 by the all-time play count, ties by
/// the most recent play.
List<RankRow> buildMostPlayed(Library library) {
  final played = library.tracks.where((t) => t.playCount > 0).toList()
    ..sort((a, b) {
      final byCount = b.playCount.compareTo(a.playCount);
      if (byCount != 0) return byCount;
      final x = a.lastPlayedAt, y = b.lastPlayedAt;
      if (x == null || y == null) {
        return x == y ? 0 : (x == null ? 1 : -1);
      }
      return y.compareTo(x);
    });
  if (played.isEmpty) return const [];
  final top = played.first.playCount;
  return [
    for (final t in played.take(5)) _songRow(t, t.playCount, t.playCount / top),
  ];
}
