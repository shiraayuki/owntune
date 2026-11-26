import 'package:drift/drift.dart';
import 'package:owntune/data/db/database.dart';

/// Reads and writes the measured loudness of tracks (`track_loudness`).
class LoudnessRepository {
  LoudnessRepository(this._db);

  final AppDatabase _db;

  /// The newest track that still needs measuring: no row yet, or a failure
  /// recorded by a measurer older than [version].
  Future<Track?> nextUnmeasured(int version) {
    final l = _db.trackLoudness;
    final query =
        _db.select(_db.tracks).join([
            leftOuterJoin(l, l.trackId.equalsExp(_db.tracks.id)),
          ])
          ..where(
            l.trackId.isNull() |
                (l.lufs.isNull() &
                    (l.failedVersion.isNull() |
                        l.failedVersion.isSmallerThanValue(version))),
          )
          ..orderBy([
            OrderingTerm.desc(_db.tracks.addedAt),
            OrderingTerm.desc(_db.tracks.id),
          ])
          ..limit(1);
    return query.map((row) => row.readTable(_db.tracks)).getSingleOrNull();
  }

  /// Stores [lufs] for [trackId]; nothing if the track is gone.
  Future<void> saveMeasured(int trackId, double lufs) => _saveIfTrackExists(
    TrackLoudnessCompanion.insert(
      trackId: Value(trackId),
      lufs: Value(lufs),
      failedVersion: const Value(null),
    ),
  );

  /// Records that measurer [version] could not measure [trackId]; nothing if
  /// the track is gone.
  Future<void> saveFailed(int trackId, int version) => _saveIfTrackExists(
    TrackLoudnessCompanion.insert(
      trackId: Value(trackId),
      lufs: const Value(null),
      failedVersion: Value(version),
    ),
  );

  /// The measured loudness of [trackId], or null if it has none.
  Future<double?> lufsOf(int trackId) async {
    final row = await (_db.select(
      _db.trackLoudness,
    )..where((l) => l.trackId.equals(trackId))).getSingleOrNull();
    return row?.lufs;
  }

  Future<void> _saveIfTrackExists(TrackLoudnessCompanion row) =>
      _db.transaction(() async {
        final track = await (_db.select(
          _db.tracks,
        )..where((t) => t.id.equals(row.trackId.value))).getSingleOrNull();
        if (track == null) return;
        await _db.into(_db.trackLoudness).insertOnConflictUpdate(row);
      });
}
