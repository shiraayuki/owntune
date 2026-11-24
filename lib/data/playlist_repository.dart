import 'dart:io';

import 'package:drift/drift.dart';

import 'db/database.dart';
import 'library_storage.dart';
import 'track_repository.dart';

/// What [PlaylistRepository.saveEdit] does with the playlist's cover.
sealed class PlaylistCoverChange {
  const PlaylistCoverChange();
}

class PlaylistCoverKeep extends PlaylistCoverChange {
  const PlaylistCoverKeep();
}

/// Replaces the cover with this JPEG.
class PlaylistCoverSet extends PlaylistCoverChange {
  const PlaylistCoverSet(this.jpeg);

  final Uint8List jpeg;
}

class PlaylistCoverRemove extends PlaylistCoverChange {
  const PlaylistCoverRemove();
}

/// Persistence for playlists and their entries. Cover files are shared with
/// tracks (same hash, same file), so a cover is only deleted when neither a
/// track nor a playlist uses it.
class PlaylistRepository {
  PlaylistRepository(this._db, this._storage, {required this._hash});

  final AppDatabase _db;
  final LibraryStorage _storage;
  final String Function(Uint8List) _hash;

  Stream<List<Playlist>> watchPlaylists() => _db.select(_db.playlists).watch();

  Stream<List<PlaylistEntry>> watchEntries() =>
      _db.select(_db.playlistEntries).watch();

  /// Creates an empty playlist (or one with [cover]) and returns its id.
  Future<int> create(String name, {Uint8List? cover}) async {
    final coverFile = cover == null ? null : await _storeCover(cover);
    return _db
        .into(_db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: name.trim(),
            createdAt: DateTime.now(),
            coverFile: Value(coverFile),
          ),
        );
  }

  /// Appends [trackIds] at the end, in order, duplicates included.
  Future<void> addTracks(int playlistId, List<int> trackIds) async {
    if (trackIds.isEmpty) return;
    await _db.transaction(() async {
      final maxPosition = _db.playlistEntries.position.max();
      final query = _db.selectOnly(_db.playlistEntries)
        ..addColumns([maxPosition])
        ..where(_db.playlistEntries.playlistId.equals(playlistId));
      var next = ((await query.getSingle()).read(maxPosition) ?? -1) + 1;
      for (final trackId in trackIds) {
        await _db
            .into(_db.playlistEntries)
            .insert(
              PlaylistEntriesCompanion.insert(
                playlistId: playlistId,
                trackId: trackId,
                position: next++,
              ),
            );
      }
    });
  }

  /// Removes one entry (not every copy of its song) and renumbers the rest of
  /// its playlist densely from 0.
  Future<void> removeEntry(int entryId) => _db.transaction(() async {
    final entry = await (_db.select(
      _db.playlistEntries,
    )..where((e) => e.id.equals(entryId))).getSingleOrNull();
    if (entry == null) return;
    await (_db.delete(
      _db.playlistEntries,
    )..where((e) => e.id.equals(entryId))).go();
    final rest =
        await (_db.select(_db.playlistEntries)
              ..where((e) => e.playlistId.equals(entry.playlistId))
              ..orderBy([(e) => OrderingTerm.asc(e.position)]))
            .get();
    for (var i = 0; i < rest.length; i++) {
      if (rest[i].position == i) continue;
      await (_db.update(_db.playlistEntries)
            ..where((e) => e.id.equals(rest[i].id)))
          .write(PlaylistEntriesCompanion(position: Value(i)));
    }
  });

  /// Applies the Edit Playlist screen in one transaction: the trimmed [name],
  /// the entries in [entryIds] in that order (entries of this playlist that
  /// are not listed are deleted; ids that no longer exist are ignored) and
  /// the [cover] change.
  Future<void> saveEdit(
    int playlistId, {
    required String name,
    required List<int> entryIds,
    required PlaylistCoverChange cover,
  }) async {
    final newCover = switch (cover) {
      PlaylistCoverSet(:final jpeg) => await _storeCover(jpeg),
      _ => null,
    };
    String? oldCover;
    await _db.transaction(() async {
      final current = await (_db.select(
        _db.playlists,
      )..where((p) => p.id.equals(playlistId))).getSingleOrNull();
      if (current == null) return;
      oldCover = current.coverFile;
      await (_db.update(
        _db.playlists,
      )..where((p) => p.id.equals(playlistId))).write(
        PlaylistsCompanion(
          name: Value(name.trim()),
          coverFile: switch (cover) {
            PlaylistCoverKeep() => const Value.absent(),
            PlaylistCoverSet() => Value(newCover),
            PlaylistCoverRemove() => const Value(null),
          },
        ),
      );
      await (_db.delete(_db.playlistEntries)..where(
            (e) => e.playlistId.equals(playlistId) & e.id.isNotIn(entryIds),
          ))
          .go();
      // Count only the rows that exist, so a vanished id leaves no gap.
      var position = 0;
      for (final entryId in entryIds) {
        final written =
            await (_db.update(_db.playlistEntries)..where(
                  (e) => e.id.equals(entryId) & e.playlistId.equals(playlistId),
                ))
                .write(PlaylistEntriesCompanion(position: Value(position)));
        if (written > 0) position++;
      }
    });
    final old = oldCover;
    if (cover is! PlaylistCoverKeep) await _deleteCoverIfUnused(old);
  }

  /// Removes the playlist and its entries, then its cover file if nothing else
  /// uses it.
  Future<void> delete(int playlistId) async {
    final current = await (_db.select(
      _db.playlists,
    )..where((p) => p.id.equals(playlistId))).getSingleOrNull();
    if (current == null) return;
    await _db.transaction(() async {
      await (_db.delete(
        _db.playlistEntries,
      )..where((e) => e.playlistId.equals(playlistId))).go();
      await (_db.delete(
        _db.playlists,
      )..where((p) => p.id.equals(playlistId))).go();
    });
    await _deleteCoverIfUnused(current.coverFile);
  }

  Future<String> _storeCover(Uint8List jpeg) async {
    final name = '${_hash(jpeg)}.jpg';
    await _storage.storeCover(name, jpeg);
    return name;
  }

  Future<void> _deleteCoverIfUnused(String? name) async {
    if (name == null || await isCoverInUse(_db, name)) return;
    try {
      await _storage.coverFile(name).delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}
