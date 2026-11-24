import 'package:drift/drift.dart';

import 'db/database.dart';

/// Persistence for the play history: one row per listening session.
class PlayRepository {
  PlayRepository(this._db);

  final AppDatabase _db;

  /// Writes a new session and returns its row id.
  Future<int> insert({
    required int trackId,
    required DateTime startedAt,
    required int listenedMs,
    required bool counted,
    String? sourceKind,
    String? sourceKey,
  }) => _db
      .into(_db.plays)
      .insert(
        PlaysCompanion.insert(
          trackId: trackId,
          startedAt: startedAt,
          listenedMs: listenedMs,
          counted: counted,
          sourceKind: Value(sourceKind),
          sourceKey: Value(sourceKey),
        ),
      );

  /// Updates how long a session has been heard and whether it counts.
  Future<void> update(
    int id, {
    required int listenedMs,
    required bool counted,
  }) async {
    await (_db.update(_db.plays)..where((p) => p.id.equals(id))).write(
      PlaysCompanion(listenedMs: Value(listenedMs), counted: Value(counted)),
    );
  }
}
