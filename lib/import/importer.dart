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

class ImportSummary {
  const ImportSummary({
    required this.added,
    required this.duplicates,
    required this.unsupported,
    required this.albums,
    required this.artists,
  });

  final int added;
  final int duplicates;

  /// Original names of unsupported and unreadable files, in input order.
  final List<String> unsupported;

  /// Distinct albums among the added tracks (tracks without album excluded).
  final int albums;

  /// Distinct artists among the added tracks (missing artist counts as
  /// `Unknown Artist`).
  final int artists;

  int get checked => added + duplicates + unsupported.length;
}

enum _Outcome { added, duplicate, unsupported }

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

  Future<ImportSummary> importFiles(
    List<String> paths, {
    void Function(ImportProgress)? onProgress,
  }) async {
    await _storage.ensure();

    var added = 0;
    var duplicates = 0;
    final unsupported = <String>[];
    final albums = <String>{};
    final artists = <String>{};

    for (var i = 0; i < paths.length; i++) {
      final name = p.basename(paths[i]);
      onProgress?.call(
        ImportProgress(done: i, total: paths.length, currentName: name),
      );

      final TrackInfo? info;
      final _Outcome outcome;
      (outcome, info) = await _importOne(paths[i], name);
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
      }
    }

    onProgress?.call(
      ImportProgress(done: paths.length, total: paths.length, currentName: ''),
    );
    return ImportSummary(
      added: added,
      duplicates: duplicates,
      unsupported: unsupported,
      albums: albums.length,
      artists: artists.length,
    );
  }

  /// Imports one file. Only files created by this attempt are removed on
  /// failure; files that belong to existing rows are never touched.
  Future<(_Outcome, TrackInfo?)> _importOne(String path, String name) async {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    if (!_supported.contains(ext)) return (_Outcome.unsupported, null);

    // The reader picks the parser by file extension, so the temporary copy
    // keeps the real one: `<random>.part.<ext>`.
    final part = _storage.audioFile('${_randomHex()}.part.$ext');
    File? finalFile; // set only once this attempt has renamed the part file
    File? newCover; // set only if this attempt wrote the cover file
    try {
      await File(path).copy(part.path);

      final result = await _read(part.path);
      final info = result.track;
      if (result.status != ReadStatus.ok || info == null) {
        return (_Outcome.unsupported, null);
      }

      if (await _repo.hasHash(info.contentHash)) {
        return (_Outcome.duplicate, null);
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
      return (_Outcome.added, info);
    } catch (_) {
      await _deleteQuietly(finalFile);
      final cover = newCover;
      if (cover != null &&
          !await _repo.isCoverReferenced(p.basename(cover.path))) {
        await _deleteQuietly(cover);
      }
      return (_Outcome.unsupported, null);
    } finally {
      // Gone after a successful rename; a leftover otherwise.
      await _deleteQuietly(part);
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
