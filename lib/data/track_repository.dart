import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import 'package:owntune/edit/track_tags.dart';

import 'db/database.dart';
import 'library_storage.dart';

/// Whether any track or playlist uses [name] as its cover file.
Future<bool> isCoverInUse(AppDatabase db, String name) async {
  final track =
      await (db.select(db.tracks)
            ..where((t) => t.coverFile.equals(name))
            ..limit(1))
          .getSingleOrNull();
  if (track != null) return true;
  final playlist =
      await (db.select(db.playlists)
            ..where((p) => p.coverFile.equals(name))
            ..limit(1))
          .getSingleOrNull();
  return playlist != null;
}

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

  /// Sets the tag columns of the rows in [byId], and the cover file of the
  /// rows in [coverFiles], in one transaction so the library changes in one
  /// step. Hash and file name stay as imported.
  Future<void> updateTags(
    Map<int, TrackTags> byId, {
    Map<int, String?> coverFiles = const {},
  }) => _db.transaction(() async {
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
          coverFile: coverFiles.containsKey(id)
              ? Value(coverFiles[id])
              : const Value.absent(),
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

    await _db.transaction(() async {
      await (_db.delete(_db.tracks)..where((t) => t.id.equals(id))).go();
      await (_db.delete(
        _db.trackLoudness,
      )..where((l) => l.trackId.equals(id))).go();
      await _removeFromPlaylists(id);
    });
    await _deleteIfExists(_storage.audioFile(track.fileName));

    final cover = track.coverFile;
    if (cover != null && !await isCoverReferenced(cover)) {
      await _deleteIfExists(_storage.coverFile(cover));
    }
  }

  /// Deletes the entries of [trackId] and renumbers the playlists they were in
  /// densely from 0.
  Future<void> _removeFromPlaylists(int trackId) async {
    final removed = await (_db.select(
      _db.playlistEntries,
    )..where((e) => e.trackId.equals(trackId))).get();
    if (removed.isEmpty) return;
    await (_db.delete(
      _db.playlistEntries,
    )..where((e) => e.trackId.equals(trackId))).go();
    for (final playlistId in {for (final e in removed) e.playlistId}) {
      final rest =
          await (_db.select(_db.playlistEntries)
                ..where((e) => e.playlistId.equals(playlistId))
                ..orderBy([(e) => OrderingTerm.asc(e.position)]))
              .get();
      for (var i = 0; i < rest.length; i++) {
        if (rest[i].position == i) continue;
        await (_db.update(_db.playlistEntries)
              ..where((e) => e.id.equals(rest[i].id)))
            .write(PlaylistEntriesCompanion(position: Value(i)));
      }
    }
  }

  /// Counts a play of the track: play count + 1 and `lastPlayedAt` now. Called
  /// when a listen reaches the play rule (30 s heard, or the end of a short
  /// song that was heard).
  Future<void> markPlayed(int id) async {
    await _db.customUpdate(
      'UPDATE tracks SET play_count = play_count + 1, last_played_at = ? '
      'WHERE id = ?',
      variables: [Variable(DateTime.now()), Variable(id)],
      updates: {_db.tracks},
    );
  }

  /// Likes ([liked] true) or unlikes the songs in [ids]. Liking keeps the date
  /// of songs that are already liked.
  Future<void> setLiked(Iterable<int> ids, {required bool liked}) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final marks = List.filled(list.length, '?').join(', ');
    await _db.customUpdate(
      liked
          ? 'UPDATE tracks SET liked_at = ? WHERE id IN ($marks) '
                'AND liked_at IS NULL'
          : 'UPDATE tracks SET liked_at = NULL WHERE id IN ($marks)',
      variables: [
        if (liked) Variable(DateTime.now()),
        for (final id in list) Variable(id),
      ],
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
    final playlists = await _db.select(_db.playlists).get();
    final audioNames = {for (final t in tracks) t.fileName};
    final coverNames = {
      for (final t in tracks)
        if (t.coverFile != null) t.coverFile!,
      for (final p in playlists)
        if (p.coverFile != null) p.coverFile!,
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

  /// Whether any track or playlist uses [cover] as its cover file name.
  Future<bool> isCoverReferenced(String cover) => isCoverInUse(_db, cover);

  Future<void> _deleteIfExists(File file) async {
    try {
      await file.delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}
