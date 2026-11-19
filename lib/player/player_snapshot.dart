import 'dart:convert';

import 'package:owntune/data/db/database.dart';
import 'package:owntune/player/play_queue.dart';

/// What is saved of the player so it comes back after a restart: the queue
/// as track ids, the current index, its source label, repeat, position and,
/// while shuffled, the unshuffled order.
class PlayerSnapshot {
  const PlayerSnapshot({
    required this.trackIds,
    required this.index,
    this.source,
    this.repeat = QueueRepeat.off,
    this.position = Duration.zero,
    this.shuffleOrder,
  });

  final List<int> trackIds;
  final int index;
  final String? source;
  final QueueRepeat repeat;
  final Duration position;

  /// While shuffled: the positions in [trackIds] that give the unshuffled
  /// order (track ids alone are ambiguous, a song may be queued twice).
  final List<int>? shuffleOrder;

  String toJson() => jsonEncode({
    'trackIds': trackIds,
    'index': index,
    'source': ?source,
    'repeat': repeat.name,
    'positionMs': position.inMilliseconds,
    'shuffleOrder': ?shuffleOrder,
  });

  /// Null for a missing, malformed or inconsistent value, so a broken saved
  /// state never keeps the app from starting.
  static PlayerSnapshot? tryParse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final map = jsonDecode(json);
      if (map is! Map<String, dynamic>) return null;
      final ids = map['trackIds'];
      final index = map['index'];
      final source = map['source'];
      final positionMs = map['positionMs'] ?? 0;
      if (ids is! List || ids.isEmpty || ids.any((i) => i is! int)) {
        return null;
      }
      if (index is! int || index < 0 || index >= ids.length) return null;
      if (source != null && source is! String) return null;
      if (positionMs is! int || positionMs < 0) return null;
      return PlayerSnapshot(
        trackIds: ids.cast<int>(),
        index: index,
        source: source as String?,
        repeat: QueueRepeat.values.firstWhere(
          (r) => r.name == map['repeat'],
          orElse: () => QueueRepeat.off,
        ),
        position: Duration(milliseconds: positionMs),
        shuffleOrder: _permutation(map['shuffleOrder'], ids.length),
      );
    } on FormatException {
      return null;
    }
  }
}

/// [value] if it is a permutation of `0..length-1`, else null (a broken
/// shuffle order only costs the shuffle, not the saved queue).
List<int>? _permutation(Object? value, int length) {
  if (value is! List || value.length != length) return null;
  if (value.any((p) => p is! int || p < 0 || p >= length)) return null;
  final order = value.cast<int>();
  return order.toSet().length == length ? order : null;
}

/// Where the player's [PlayerSnapshot] is kept.
abstract interface class PlayerStateStore {
  Future<PlayerSnapshot?> load();

  /// Saves [snapshot]; null removes the saved state.
  Future<void> save(PlayerSnapshot? snapshot);
}

/// [PlayerStateStore] as one JSON entry in the `settings_entries` table.
class DbPlayerStateStore implements PlayerStateStore {
  DbPlayerStateStore(this._db);

  final AppDatabase _db;

  static const key = 'player.state';

  @override
  Future<PlayerSnapshot?> load() async {
    final row = await (_db.select(
      _db.settingsEntries,
    )..where((e) => e.key.equals(key))).getSingleOrNull();
    return PlayerSnapshot.tryParse(row?.value);
  }

  @override
  Future<void> save(PlayerSnapshot? snapshot) async {
    if (snapshot == null) {
      await (_db.delete(
        _db.settingsEntries,
      )..where((e) => e.key.equals(key))).go();
    } else {
      await _db
          .into(_db.settingsEntries)
          .insertOnConflictUpdate(
            SettingsEntriesCompanion.insert(key: key, value: snapshot.toJson()),
          );
    }
  }
}
