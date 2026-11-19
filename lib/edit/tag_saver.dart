import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/edit/track_tags.dart';

/// Writes [tags] into the audio file at [path]; returns an error message, or
/// null on success. Production passes the Rust `writeTags`.
typedef WriteTags = Future<String?> Function(String path, TrackTags tags);

/// A song whose edit could not be saved.
class SaveFailure {
  const SaveFailure(this.track, this.message);

  final Track track;
  final String message;
}

/// Saves edited tags: each song's file first, then the rows of all songs
/// whose file was written, in one transaction. A failed file write leaves
/// that song's row as it was, so database and file never drift apart.
class TagSaver {
  TagSaver({required this._write, required this._storage, required this._repo});

  final WriteTags _write;
  final LibraryStorage _storage;
  final TrackRepository _repo;

  /// Applies [edit] to [tracks]; songs it does not change are skipped.
  /// Returns the songs that failed.
  Future<List<SaveFailure>> save(List<Track> tracks, TagEdit edit) async {
    final failures = <SaveFailure>[];
    final saved = <int, TrackTags>{};
    for (final t in tracks) {
      final old = TrackTags.of(t);
      final tags = edit.apply(old);
      if (tags == old) continue;
      String? error;
      try {
        error = await _write(_storage.audioFile(t.fileName).path, tags);
      } on Object catch (e) {
        error = '$e';
      }
      if (error == null) {
        saved[t.id] = tags;
      } else {
        failures.add(SaveFailure(t, error));
      }
    }
    if (saved.isNotEmpty) await _repo.updateTags(saved);
    return failures;
  }
}
