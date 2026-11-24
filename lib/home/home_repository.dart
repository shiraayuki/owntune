import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/player/queue_source.dart';

/// A place music was played from (album, artist, playlist or Liked Songs).
class RecentSource {
  const RecentSource(this.kind, this.key, this.lastPlayedAt);

  final QueueSourceKind kind;
  final String? key;
  final DateTime lastPlayedAt;

  @override
  bool operator ==(Object other) =>
      other is RecentSource &&
      other.kind == kind &&
      other.key == key &&
      other.lastPlayedAt == lastPlayedAt;

  @override
  int get hashCode => Object.hash(kind, key, lastPlayedAt);
}

/// How often a song was played (counted plays) in a time window.
class TrackPlayCount {
  const TrackPlayCount(this.trackId, this.plays);

  final int trackId;
  final int plays;

  @override
  bool operator ==(Object other) =>
      other is TrackPlayCount &&
      other.trackId == trackId &&
      other.plays == plays;

  @override
  int get hashCode => Object.hash(trackId, plays);
}

/// Live queries over the play history for the Home tab.
class HomeRepository {
  HomeRepository(this._db);

  final AppDatabase _db;

  /// The distinct album, artist, playlist and Liked Songs sources played since
  /// [since], newest first. Songs, Search, Up Next and Home rows (kind
  /// `other`) are left out. Emits only when the list changes, not on every
  /// update of the open play row.
  Stream<List<RecentSource>> watchRecentSources({
    required DateTime since,
    int limit = 20,
  }) {
    return _db
        .customSelect(
          'SELECT source_kind, source_key, MAX(started_at) AS last_at '
          'FROM plays '
          "WHERE source_kind IN ('album', 'artist', 'playlist', 'liked') "
          'AND started_at >= ? '
          'GROUP BY source_kind, source_key '
          'ORDER BY last_at DESC '
          'LIMIT ?',
          variables: [Variable<DateTime>(since), Variable<int>(limit)],
          readsFrom: {_db.plays},
        )
        .watch()
        .map((rows) {
          final sources = <RecentSource>[];
          for (final row in rows) {
            final kind = QueueSourceKind.values
                .asNameMap()[row.read<String>('source_kind')];
            if (kind == null) continue;
            sources.add(
              RecentSource(
                kind,
                row.readNullable<String>('source_key'),
                row.read<DateTime>('last_at'),
              ),
            );
          }
          return sources;
        })
        .distinct(const ListEquality<RecentSource>().equals);
  }

  /// Counted plays per song since [since], most played first; ties go to the
  /// song played last. Emits only when the list changes.
  Stream<List<TrackPlayCount>> watchTopTracks({
    required DateTime since,
    int limit = 50,
  }) {
    return _db
        .customSelect(
          'SELECT track_id, COUNT(*) AS plays, MAX(started_at) AS last_at '
          'FROM plays '
          'WHERE counted = 1 AND started_at >= ? '
          'GROUP BY track_id '
          'ORDER BY plays DESC, last_at DESC '
          'LIMIT ?',
          variables: [Variable<DateTime>(since), Variable<int>(limit)],
          readsFrom: {_db.plays},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              TrackPlayCount(row.read<int>('track_id'), row.read<int>('plays')),
          ],
        )
        .distinct(const ListEquality<TrackPlayCount>().equals);
  }
}
