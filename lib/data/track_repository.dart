import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import 'package:owntune/edit/track_tags.dart';

import 'db/database.dart';
import 'library_storage.dart';

/// Persistence for imported tracks: database rows plus the files they own.
class TrackRepository {
  TrackRepository(this._db, this._storage);

  final AppDatabase _db;
  final LibraryStorage _storage;

  Stream<List<Track>> watchAll() => _db.select(_db.tracks).watch();

  Future<bool> hasHash(String hash) async {
    final row =
        await (_db.select(_db.tracks)
              ..where((t) => t.contentHash.equals(hash))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> insert(TracksCompanion row) async {
    await _db.into(_db.tracks).insert(row);
  }

  /// Sets the tag columns of the rows in [byId], in one transaction so the
  /// library changes in one step. Hash and file name stay as imported.
  Future<void> updateTags(Map<int, TrackTags> byId) =>
      _db.transaction(() async {
        for (final MapEntry(key: id, value: t) in byId.entries) {
          await (_db.update(_db.tracks)..where((r) => r.id.equals(id))).write(
            TracksCompanion(
              title: Value(t.title),
              artist: Value(t.artist),
              album: Value(t.album),
              albumArtist: Value(t.albumArtist),
              genre: Value(t.genre),
              trackNumber: Value(t.trackNumber),
              discNumber: Value(t.discNumber),
              year: Value(t.year),
            ),
          );
        }
      });

  /// Removes the row and its audio file, plus the cover file if no other row
  /// references it.
  Future<void> delete(int id) async {
    final track = await (_db.select(
      _db.tracks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (track == null) return;

    await (_db.delete(_db.tracks)..where((t) => t.id.equals(id))).go();
    await _deleteIfExists(_storage.audioFile(track.fileName));

    final cover = track.coverFile;
    if (cover != null && !await isCoverReferenced(cover)) {
      await _deleteIfExists(_storage.coverFile(cover));
    }
  }

  /// Counts a play of the track that just ended: play count + 1 and
  /// `lastPlayedAt` now.
  Future<void> markPlayed(int id) async {
    await _db.customUpdate(
      'UPDATE tracks SET play_count = play_count + 1, last_played_at = ? '
      'WHERE id = ?',
      variables: [Variable(DateTime.now()), Variable(id)],
      updates: {_db.tracks},
    );
  }

  Future<int> count() async {
    final countExp = _db.tracks.id.count();
    final query = _db.selectOnly(_db.tracks)..addColumns([countExp]);
    return (await query.getSingle()).read(countExp) ?? 0;
  }

  /// Total size in bytes of all files in the audio and covers directories.
  Future<int> storageBytes() async {
    var total = 0;
    for (final dir in [_storage.audioDir, _storage.coversDir]) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is File) total += await entity.length();
      }
    }
    return total;
  }

  /// Deletes leftovers of interrupted imports: every `*.part` file, every
  /// audio file without a row and every cover without a referencing row.
  ///
  /// Startup-only and best-effort: a file that cannot be deleted (or a folder
  /// that cannot be listed) is skipped and retried on the next start. Database
  /// errors still propagate.
  Future<void> cleanupOrphans() async {
    final tracks = await _db.select(_db.tracks).get();
    final audioNames = {for (final t in tracks) t.fileName};
    final coverNames = {
      for (final t in tracks)
        if (t.coverFile != null) t.coverFile!,
    };

    await _deleteUnreferenced(_storage.audioDir, audioNames);
    await _deleteUnreferenced(_storage.coversDir, coverNames);
  }

  Future<void> _deleteUnreferenced(Directory dir, Set<String> keep) async {
    final List<FileSystemEntity> entries;
    try {
      if (!await dir.exists()) return;
      entries = await dir.list().toList();
    } on FileSystemException {
      return;
    }
    for (final entity in entries) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith('.part') || !keep.contains(name)) {
        try {
          await entity.delete();
        } on FileSystemException {
          // Gone already or not deletable now; the next start tries again.
        }
      }
    }
  }

  /// Whether any row uses [cover] as its cover file name.
  Future<bool> isCoverReferenced(String cover) async {
    final row =
        await (_db.select(_db.tracks)
              ..where((t) => t.coverFile.equals(cover))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      await file.delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}
