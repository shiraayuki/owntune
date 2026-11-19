import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/src/rust/api/library.dart';
import 'package:path/path.dart' as p;

/// Reads tags, duration, hash and cover of the audio file at a path.
/// Production code passes `(path) => readTrack(path: path)`.
typedef TrackReader = Future<ReadResult> Function(String path);

class ImportProgress {
  const ImportProgress({
    required this.done,
    required this.total,
    required this.currentName,
  });

  /// Files fully processed so far.
  final int done;
  final int total;

  /// Original name of the file about to be processed; empty on completion.
  final String currentName;
}

/// A file that has a supported extension but could not be imported.
typedef ImportFailure = ({String name, String reason});

class ImportSummary {
  const ImportSummary({
    required this.added,
    required this.duplicates,
    required this.unsupported,
    this.failures = const [],
    required this.albums,
    required this.artists,
  });

  final int added;
  final int duplicates;

  /// Original names of unsupported and unreadable files, in input order.
  final List<String> unsupported;

  /// Why each file with a supported extension in [unsupported] failed (a
  /// subset of it, same order). The iPhone has no logs, so the summary shows
  /// these reasons.
  final List<ImportFailure> failures;

  /// Distinct albums among the added tracks (tracks without album excluded).
  final int albums;

  /// Distinct artists among the added tracks (missing artist counts as
  /// `Unknown Artist`).
  final int artists;

  int get checked => added + duplicates + unsupported.length;
}

enum _Outcome { added, duplicate, unsupported }

/// Result of one file: the outcome, the track if added, and the reason if a
/// file with a supported extension failed.
typedef _FileResult = (_Outcome, TrackInfo?, String?);

/// Copies picked files into the app library, reads their metadata and
/// inserts a row per new track.
class Importer {
  Importer({
    required this._repo,
    required this._storage,
    required this._read,
    required Set<String> supportedExtensions,
  }) : _supported = {for (final e in supportedExtensions) e.toLowerCase()};

  final TrackRepository _repo;
  final LibraryStorage _storage;
  final TrackReader _read;
  final Set<String> _supported;
  final _random = Random.secure();
  bool _running = false;

  /// Imports [paths] one after another and reports a summary.
  ///
  /// Only one import may run at a time: a call made while another is still
  /// pending fails with a [StateError] and leaves the running import
  /// undisturbed. Concurrent imports could race on the same content hash and
  /// on shared cover files.
  Future<ImportSummary> importFiles(
    List<String> paths, {
    void Function(ImportProgress)? onProgress,
  }) async {
    if (_running) throw StateError('An import is already running');
    _running = true;
    try {
      return await _importAll(paths, onProgress);
    } finally {
      _running = false;
    }
  }

  Future<ImportSummary> _importAll(
    List<String> paths,
    void Function(ImportProgress)? onProgress,
  ) async {
    await _storage.ensure();

    var added = 0;
    var duplicates = 0;
    final unsupported = <String>[];
    final failures = <ImportFailure>[];
    final albums = <String>{};
    final artists = <String>{};

    for (var i = 0; i < paths.length; i++) {
      final name = p.basename(paths[i]);
      onProgress?.call(
        ImportProgress(done: i, total: paths.length, currentName: name),
      );

      final (outcome, info, reason) = await _importOne(paths[i], name);
      switch (outcome) {
        case _Outcome.added:
          added++;
          artists.add(displayArtist(info!.artist));
          final album = info.album?.trim();
          if (album != null && album.isNotEmpty) albums.add(album);
        case _Outcome.duplicate:
          duplicates++;
        case _Outcome.unsupported:
          unsupported.add(name);
          if (reason != null) failures.add((name: name, reason: reason));
      }
    }

    onProgress?.call(
      ImportProgress(done: paths.length, total: paths.length, currentName: ''),
    );
    return ImportSummary(
      added: added,
      duplicates: duplicates,
      unsupported: unsupported,
      failures: failures,
      albums: albums.length,
      artists: artists.length,
    );
  }

  /// Imports one file. Only files created by this attempt are removed on
  /// failure; files that belong to existing rows are never touched.
  Future<_FileResult> _importOne(String path, String name) async {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    if (!_supported.contains(ext)) return (_Outcome.unsupported, null, null);

    // The reader picks the parser by file extension, so the temporary copy
    // keeps the real one: `<random>.part.<ext>`.
    final part = _storage.audioFile('${_randomHex()}.part.$ext');
    String? hash; // set once the reader succeeded
    File? finalFile; // set only once this attempt has renamed the part file
    File? newCover; // set only if this attempt wrote the cover file
    try {
      await File(path).copy(part.path);

      final result = await _read(part.path);
      final info = result.track;
      if (result.status != ReadStatus.ok || info == null) {
        return (_Outcome.unsupported, null, _readFailure(result));
      }

      hash = info.contentHash;
      if (await _repo.hasHash(info.contentHash)) {
        return (_Outcome.duplicate, null, null);
      }

      String? coverName;
      final cover = info.cover;
      if (cover != null) {
        coverName = '${cover.hash}.${cover.fileExtension}';
        final coverFile = _storage.coverFile(coverName);
        if (!await coverFile.exists()) {
          await _writeCover(coverFile, cover);
          newCover = coverFile;
        }
      }

      final fileName = '${info.contentHash}.$ext';
      final target = _storage.audioFile(fileName);
      await part.rename(target.path);
      finalFile = target;

      await _repo.insert(
        TracksCompanion.insert(
          fileName: fileName,
          originalName: name,
          contentHash: info.contentHash,
          durationMs: info.durationMs,
          addedAt: DateTime.now(),
          title: Value(info.title),
          artist: Value(info.artist),
          album: Value(info.album),
          albumArtist: Value(info.albumArtist),
          genre: Value(info.genre),
          trackNumber: Value(info.trackNumber),
          discNumber: Value(info.discNumber),
          year: Value(info.year),
          coverFile: Value(coverName),
        ),
      );
      return (_Outcome.added, info, null);
    } catch (e) {
      await _rollback(hash: hash, finalFile: finalFile, newCover: newCover);
      return (_Outcome.unsupported, null, e.toString());
    } finally {
      // Gone after a successful rename; a leftover otherwise.
      await _deleteQuietly(part);
    }
  }

  static String _readFailure(ReadResult result) {
    final message = result.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    return result.status == ReadStatus.unsupported
        ? 'Format not supported'
        : 'Could not be read';
  }

  /// Removes what a failed attempt created, but never a file a row owns: the
  /// audio file only if no row has its hash (another attempt may have won the
  /// race for it), the cover only if no row references it. If a check itself
  /// fails, the file is kept; startup cleanup removes true orphans.
  Future<void> _rollback({
    required String? hash,
    required File? finalFile,
    required File? newCover,
  }) async {
    try {
      if (finalFile != null && hash != null && !await _repo.hasHash(hash)) {
        await _deleteQuietly(finalFile);
      }
      if (newCover != null &&
          !await _repo.isCoverReferenced(p.basename(newCover.path))) {
        await _deleteQuietly(newCover);
      }
    } catch (_) {
      // Keep the files; see above.
    }
  }

  /// Writes via a temporary file so an interrupted write never leaves a
  /// truncated cover under its final name.
  Future<void> _writeCover(File target, CoverArt cover) async {
    final tmp = _storage.coverFile('${_randomHex()}.part');
    try {
      await tmp.writeAsBytes(cover.data, flush: true);
      await tmp.rename(target.path);
    } finally {
      await _deleteQuietly(tmp);
    }
  }

  String _randomHex() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone or not deletable; nothing more to do.
    }
  }
}
