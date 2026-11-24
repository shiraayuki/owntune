import 'dart:convert';

import 'package:owntune/data/db/database.dart';
import 'package:owntune/player/play_queue.dart';
import 'package:owntune/player/queue_source.dart';

/// What is saved of the player so it comes back after a restart: the queue
/// as track ids, the current index, its source, repeat, position, which entries
/// were queued with Play Next / Later and, while shuffled, the unshuffled
/// order.
class PlayerSnapshot {
  const PlayerSnapshot({
    required this.trackIds,
    required this.index,
    this.source,
    this.repeat = QueueRepeat.off,
    this.position = Duration.zero,
    this.shuffleOrder,
    this.queuedPositions,
  });

  final List<int> trackIds;
  final int index;
  final QueueSource? source;
  final QueueRepeat repeat;
  final Duration position;

  /// While shuffled: the positions in [trackIds] that give the unshuffled
  /// order (track ids alone are ambiguous, a song may be queued twice).
  final List<int>? shuffleOrder;

  /// The positions in [trackIds] of entries added with Play Next / Later.
  final List<int>? queuedPositions;

  String toJson() => jsonEncode({
    'trackIds': trackIds,
    'index': index,
    'source': ?source?.label,
    'sourceKind': ?source?.kind.name,
    'sourceKey': ?source?.key,
    'repeat': repeat.name,
    'positionMs': position.inMilliseconds,
    'shuffleOrder': ?shuffleOrder,
    'queuedPositions': ?queuedPositions,
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
      final positionMs = map['positionMs'] ?? 0;
      if (ids is! List || ids.isEmpty || ids.any((i) => i is! int)) {
        return null;
      }
      if (index is! int || index < 0 || index >= ids.length) return null;
      if (positionMs is! int || positionMs < 0) return null;
      return PlayerSnapshot(
        trackIds: ids.cast<int>(),
        index: index,
        source: _source(map['source'], map['sourceKind'], map['sourceKey']),
        repeat: QueueRepeat.values.firstWhere(
          (r) => r.name == map['repeat'],
          orElse: () => QueueRepeat.off,
        ),
        position: Duration(milliseconds: positionMs),
        shuffleOrder: _permutation(map['shuffleOrder'], ids.length),
        queuedPositions: _positions(map['queuedPositions'], ids.length),
      );
    } on FormatException {
      return null;
    }
  }
}

/// The saved source; an old snapshot has only a label and gets kind `other`.
/// Null without a label, so a broken source never costs the saved queue.
QueueSource? _source(Object? label, Object? kind, Object? key) {
  if (label is! String) return null;
  return QueueSource(
    QueueSourceKind.values.firstWhere(
      (k) => k.name == kind,
      orElse: () => QueueSourceKind.other,
    ),
    label,
    key: key is String ? key : null,
  );
}

/// [value] if it is a list of positions within `0..length-1`, else null.
List<int>? _positions(Object? value, int length) {
  if (value is! List || value.any((p) => p is! int || p < 0 || p >= length)) {
    return null;
  }
  return value.cast<int>();
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
