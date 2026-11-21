import 'dart:io';
import 'dart:typed_data';

import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/edit/track_tags.dart';

/// Writes [tags] and the [cover] change into the audio file at [path];
/// returns an error message, or null on success. Production passes the Rust
/// `writeTags`.
typedef WriteTags = Future<String?> Function(
  String path,
  TrackTags tags,
  CoverEdit cover,
);

/// A song whose edit could not be saved.
class SaveFailure {
  const SaveFailure(this.track, this.message);

  final Track track;
  final String message;
}

/// Saves edited tags and covers: each song's file first, then the rows of
/// all songs whose file was written, in one transaction. A failed file write
/// leaves that song's row as it was, so database and file never drift apart.
class TagSaver {
  TagSaver({
    required this._write,
    required this._storage,
    required this._repo,
    required this._hash,
  });

  final WriteTags _write;
  final LibraryStorage _storage;
  final TrackRepository _repo;

  /// BLAKE3 hex of image bytes (Rust `hashBytes`); new covers are stored
  /// under it.
  final String Function(Uint8List) _hash;

  /// Applies [edit] to [tracks]; songs it does not change are skipped.
  /// Returns the songs that failed.
  Future<List<SaveFailure>> save(List<Track> tracks, TagEdit edit) async {
    final cover = edit.cover;
    final failures = <SaveFailure>[];
    final saved = <int, TrackTags>{};
    final coverFiles = <int, String?>{};
    final replaced = <String>{};
    String? newCover; // the file name a CoverSet is stored under
    var storedNew = false; // this save created that file

    for (final t in tracks) {
      final old = TrackTags.of(t);
      final tags = edit.apply(old);
      final coverChanges =
          cover is CoverSet || (cover is CoverRemove && t.coverFile != null);
      if (tags == old && !coverChanges) continue;
      if (cover is CoverSet && newCover == null) {
        final ext = cover.mime == 'image/png' ? 'png' : 'jpg';
        newCover = '${_hash(cover.data)}.$ext';
        try {
          storedNew = await _storage.storeCover(newCover, cover.data);
        } on Object catch (e) {
          return [for (final t in tracks) SaveFailure(t, '$e')];
        }
      }
      String? error;
      try {
        error = await _write(
          _storage.audioFile(t.fileName).path,
          tags,
          coverChanges ? cover : const CoverKeep(),
        );
      } on Object catch (e) {
        error = '$e';
      }
      if (error != null) {
        failures.add(SaveFailure(t, error));
        continue;
      }
      saved[t.id] = tags;
      if (coverChanges) {
        coverFiles[t.id] = cover is CoverSet ? newCover : null;
        if (t.coverFile != null && t.coverFile != newCover) {
          replaced.add(t.coverFile!);
        }
      }
    }

    if (saved.isNotEmpty) {
      await _repo.updateTags(saved, coverFiles: coverFiles);
    } else if (storedNew) {
      await _deleteCover(newCover!);
    }
    for (final name in replaced) {
      try {
        if (!await _repo.isCoverReferenced(name)) await _deleteCover(name);
      } on Object {
        // Best effort; startup cleanup removes leftovers.
      }
    }
    return failures;
  }

  Future<void> _deleteCover(String name) async {
    try {
      await _storage.coverFile(name).delete();
    } on FileSystemException {
      // Already gone; startup cleanup removes true orphans.
    }
  }
}
