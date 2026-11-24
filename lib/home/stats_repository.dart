import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:owntune/data/db/database.dart';

/// Counted plays and total listening time of one song in a time range.
class TrackTotal {
  const TrackTotal(this.trackId, this.plays, this.listenedMs);

  final int trackId;
  final int plays;
  final int listenedMs;

  @override
  bool operator ==(Object other) =>
      other is TrackTotal &&
      other.trackId == trackId &&
      other.plays == plays &&
      other.listenedMs == listenedMs;

  @override
  int get hashCode => Object.hash(trackId, plays, listenedMs);
}

/// How [StatsRepository.watchListeningBuckets] groups the history.
enum StatsBucket { day, month }

/// Listening time and counted plays of one local day or month.
class ListeningBucket {
  const ListeningBucket(this.start, this.listenedMs, this.plays);

  /// Local midnight of the day, or local midnight of the 1st of the month.
  final DateTime start;
  final int listenedMs;
  final int plays;

  @override
  bool operator ==(Object other) =>
      other is ListeningBucket &&
      other.start == start &&
      other.listenedMs == listenedMs &&
      other.plays == plays;

  @override
  int get hashCode => Object.hash(start, listenedMs, plays);
}

/// One row of the play history, as [StatsRepository.watchRowsOfDay] returns
/// it.
typedef StatsPlayRow = ({DateTime startedAt, bool counted, int listenedMs});

/// Live aggregate queries over the play history for the Home Stats page.
///
/// A play is a row with `counted = 1`; listening time sums `listened_ms` over
/// all rows. Ranges are `[from, to)`, grouping uses local time. Every stream
/// emits only when its result changes, so the open play row's five-second
/// updates do not rebuild the page unless an aggregate moved.
class StatsRepository {
  StatsRepository(this._db);

  final AppDatabase _db;

  /// Counted plays and listening time per song in `[from, to)`.
  Stream<List<TrackTotal>> watchTrackTotals({
    required DateTime from,
    required DateTime to,
  }) {
    return _db
        .customSelect(
          'SELECT track_id, SUM(counted) AS plays, '
          'SUM(listened_ms) AS listened '
          'FROM plays '
          'WHERE started_at >= ? AND started_at < ? '
          'GROUP BY track_id '
          'ORDER BY track_id',
          variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
          readsFrom: {_db.plays},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              TrackTotal(
                row.read<int>('track_id'),
                row.read<int>('plays'),
                row.read<int>('listened'),
              ),
          ],
        )
        .distinct(const ListEquality<TrackTotal>().equals);
  }

  /// Listening time and counted plays per local day or month in `[from, to)`,
  /// oldest first. Buckets without plays are left out. With [countedOnly]
  /// only counted rows are read (and summed), as the streak needs.
  Stream<List<ListeningBucket>> watchListeningBuckets({
    required DateTime from,
    required DateTime to,
    required StatsBucket bucket,
    bool countedOnly = false,
  }) {
    final format = switch (bucket) {
      StatsBucket.day => '%Y-%m-%d',
      StatsBucket.month => '%Y-%m',
    };
    return _db
        .customSelect(
          "SELECT strftime('$format', started_at, 'unixepoch', 'localtime') "
          'AS bucket, SUM(listened_ms) AS listened, SUM(counted) AS plays '
          'FROM plays '
          'WHERE started_at >= ? AND started_at < ? '
          '${countedOnly ? 'AND counted = 1 ' : ''}'
          'GROUP BY bucket '
          'ORDER BY bucket',
          variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
          readsFrom: {_db.plays},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              ListeningBucket(
                _parseBucket(row.read<String>('bucket')),
                row.read<int>('listened'),
                row.read<int>('plays'),
              ),
          ],
        )
        .distinct(const ListEquality<ListeningBucket>().equals);
  }

  /// Listening time per local hour of the day (24 entries) in `[from, to)`.
  Stream<List<int>> watchHourly({
    required DateTime from,
    required DateTime to,
  }) {
    return _db
        .customSelect(
          "SELECT CAST(strftime('%H', started_at, 'unixepoch', 'localtime') "
          'AS INTEGER) AS hour, SUM(listened_ms) AS listened '
          'FROM plays '
          'WHERE started_at >= ? AND started_at < ? '
          'GROUP BY hour',
          variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
          readsFrom: {_db.plays},
        )
        .watch()
        .map((rows) {
          final hours = List<int>.filled(24, 0);
          for (final row in rows) {
            hours[row.read<int>('hour')] = row.read<int>('listened');
          }
          return hours;
        })
        .distinct(const ListEquality<int>().equals);
  }

  /// The first counted play and the number of counted plays of every song that
  /// has one, over the whole history.
  Stream<Map<int, ({DateTime first, int counted})>> watchTrackHistory() {
    return _db
        .customSelect(
          'SELECT track_id, MIN(started_at) AS first_at, COUNT(*) AS counted '
          'FROM plays '
          'WHERE counted = 1 '
          'GROUP BY track_id',
          readsFrom: {_db.plays},
        )
        .watch()
        .map(
          (rows) => {
            for (final row in rows)
              row.read<int>('track_id'): (
                first: row.read<DateTime>('first_at'),
                counted: row.read<int>('counted'),
              ),
          },
        )
        .distinct(
          const MapEquality<int, ({DateTime first, int counted})>().equals,
        );
  }

  /// Every row (counted or not) that started on the local day [day], from
  /// [day] to the next local midnight, oldest first. The Stats page cuts the
  /// comparison day of the previous range from these at an exact time.
  Stream<List<StatsPlayRow>> watchRowsOfDay({required DateTime day}) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    return _db
        .customSelect(
          'SELECT started_at, counted, listened_ms '
          'FROM plays '
          'WHERE started_at >= ? AND started_at < ? '
          'ORDER BY started_at, id',
          variables: [Variable<DateTime>(start), Variable<DateTime>(end)],
          readsFrom: {_db.plays},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              (
                startedAt: row.read<DateTime>('started_at'),
                counted: row.read<bool>('counted'),
                listenedMs: row.read<int>('listened_ms'),
              ),
          ],
        )
        .distinct(const ListEquality<StatsPlayRow>().equals);
  }

  /// The number of counted plays in the whole history.
  Stream<int> watchCountedPlays() {
    return _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM plays WHERE counted = 1',
          readsFrom: {_db.plays},
        )
        .watch()
        .map((rows) => rows.single.read<int>('n'))
        .distinct();
  }

  /// The start of the earliest row (counted or not), or null without history.
  Stream<DateTime?> watchFirstPlayAt() {
    return _db
        .customSelect(
          'SELECT MIN(started_at) AS first_at FROM plays',
          readsFrom: {_db.plays},
        )
        .watch()
        .map((rows) => rows.single.readNullable<DateTime>('first_at'))
        .distinct();
  }
}

/// `2026-11-24` or `2026-11` as a local date.
DateTime _parseBucket(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts.length > 2 ? parts[2] : 1);
}
