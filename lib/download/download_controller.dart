import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/cover_image.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/download/stream_download.dart';
import 'package:owntune/edit/track_tags.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Writes [tags] and [cover] into the downloaded file at [path]; returns an
/// error message, or null on success. Production passes the Rust
/// `writeTags`.
typedef WriteDownloadTags = Future<String?> Function(
  String path,
  TrackTags tags,
  CoverBytes? cover,
);

/// The app-wide download queue. Runs one job at a time: resolve the stream,
/// download it into its own temp folder, fetch the cover, write tags and
/// cover into the file, then hand it to the Importer with its source key.
/// The folder of a job that ends as done or duplicate is deleted. A failed or
/// cancelled job keeps it (with the part file and its checkpoint), so Retry
/// continues where the download stopped; `clearFinished` and the next start
/// delete what is left.
class DownloadController extends Notifier<List<DownloadJob>> {
  var _nextId = 1;
  var _running = false;
  int? _runningId;
  CancelToken? _cancel;
  final _random = Random.secure();

  /// The folder of each job that has one, by job id. Retry keeps the id.
  final _folders = <int, Directory>{};

  @override
  List<DownloadJob> build() => const [];

  /// Queues [result] with the confirmed [tags]. Does nothing while a job for
  /// the same song is waiting or running. Failed and cancelled jobs of the
  /// same song are dropped with their folders (the new job starts over);
  /// done and duplicate jobs stay.
  void enqueue(OnlineResult result, TrackTags tags) {
    if (state.any(
      (j) => j.isActive && j.result.sourceKey == result.sourceKey,
    )) {
      return;
    }
    final stale = [
      for (final j in state)
        if (_isStopped(j) && j.result.sourceKey == result.sourceKey) j.id,
    ];
    for (final id in stale) {
      _deleteFolder(id);
    }
    state = [
      for (final j in state)
        if (!stale.contains(j.id)) j,
      DownloadJob(id: _nextId++, result: result, tags: tags),
    ];
    _pump();
  }

  /// Stops a waiting or downloading job.
  void cancel(int id) {
    final job = _job(id);
    if (job == null) return;
    if (job.phase == DownloadPhase.waiting) {
      _set(id, (j) => j.copyWith(phase: DownloadPhase.cancelled));
    } else if (job.phase == DownloadPhase.downloading && id == _runningId) {
      _cancel?.cancel();
    }
  }

  /// Queues a failed or cancelled job again, at the end. Does nothing while
  /// a job for the same song is waiting or running.
  void retry(int id) {
    final job = _job(id);
    if (job == null ||
        (job.phase != DownloadPhase.failed &&
            job.phase != DownloadPhase.cancelled)) {
      return;
    }
    // Same guard as [enqueue]: the song may have been queued again since.
    if (state.any(
      (j) => j.isActive && j.result.sourceKey == job.result.sourceKey,
    )) {
      return;
    }
    state = [
      for (final j in state)
        if (j.id != id) j,
      DownloadJob(id: job.id, result: job.result, tags: job.tags),
    ];
    _pump();
  }

  /// Drops every job that is no longer waiting or running, with its folder.
  void clearFinished() {
    for (final j in state) {
      if (!j.isActive) _deleteFolder(j.id);
    }
    state = [
      for (final j in state)
        if (j.isActive) j,
    ];
  }

  static bool _isStopped(DownloadJob j) =>
      j.phase == DownloadPhase.failed || j.phase == DownloadPhase.cancelled;

  /// Deletes the folder of job [id] in the background, if it has one. Best
  /// effort: startup empties the download folder anyway.
  void _deleteFolder(int id) => unawaited(_deleteFolderNow(id));

  /// Deletes the folder of job [id], if it has one, and completes when it is
  /// gone. Never throws.
  Future<void> _deleteFolderNow(int id) async {
    final folder = _folders.remove(id);
    if (folder == null) return;
    try {
      await folder.delete(recursive: true);
    } on Object {
      // Best effort; the next start empties the download folder.
    }
  }

  DownloadJob? _job(int id) => state.where((j) => j.id == id).firstOrNull;

  void _set(int id, DownloadJob Function(DownloadJob) change) {
    if (!ref.mounted) return;
    state = [for (final j in state) j.id == id ? change(j) : j];
  }

  void _pump() {
    if (_running) return;
    final next = state
        .where((j) => j.phase == DownloadPhase.waiting)
        .firstOrNull;
    if (next == null) return;
    _running = true;
    _run(next).whenComplete(() {
      _running = false;
      _runningId = null;
      _cancel = null;
      if (ref.mounted) _pump();
    });
  }

  Future<void> _run(DownloadJob job) async {
    final cancel = _cancel = CancelToken();
    _runningId = job.id;
    try {
      _set(job.id, (j) => j.copyWith(phase: DownloadPhase.downloading));
      final source = ref.read(onlineSourcesProvider)[job.result.source]!;
      final stream = await source.resolve(job.result);
      if (cancel.isCancelled) throw DownloadCancelled();

      final root = await ref.read(downloadDirProvider)();
      // A retry finds its folder (and the part file in it) again.
      final folder = _folders[job.id] ??= Directory(
        p.join(root.path, '${job.id}-${_random.nextInt(1 << 32)}'),
      );
      await folder.create(recursive: true);
      final part = File(p.join(folder.path, 'audio.part.${stream.extension}'));
      var percent = -1;
      await downloadStream(
        ref.read(httpTransportProvider),
        stream,
        part,
        cancel: cancel,
        onProgress: (received, total) {
          // Without a total (0 or below) there is no percent to show: report
          // once and wait for a usable total.
          final now = total > 0 ? received * 100 ~/ total : -2;
          if (now == percent) return;
          percent = now;
          _set(job.id, (j) => j.copyWith(received: received, total: total));
        },
      );

      // The job shows as downloading (with its cancel button) until the
      // import starts, so a cancel must still stop it here.
      final cover = await Future.any([
        _cover(job.result),
        cancel.whenCancelled.then((_) => null),
      ]);
      if (cancel.isCancelled) throw DownloadCancelled();
      final error = await ref.read(downloadTagWriterProvider)(
        part.path,
        job.tags,
        cover,
      );
      if (error != null) {
        throw OnlineError('The tags could not be written: $error');
      }
      // The tags changed the file, so the checkpoint no longer describes it:
      // a retry after a cancel from here on starts over (resuming would cut
      // the tagged file back to the checkpoint's length).
      try {
        await File('${part.path}.progress').delete();
      } on Object {
        // A checkpoint that stays would let a resume cut the tagged file
        // back to its old length, so the part file goes too.
        try {
          await part.delete();
        } on Object {
          // Neither can be removed: this job never looks at the folder again,
          // so a retry downloads into a fresh one.
          _folders.remove(job.id);
        }
        throw const OnlineError(
          'The download could not be finished. Try again to start over.',
        );
      }
      if (cancel.isCancelled) throw DownloadCancelled();
      final named = await part.rename(
        p.join(
          folder.path,
          '${downloadFileName(job.tags)}.${stream.extension}',
        ),
      );

      _set(job.id, (j) => j.copyWith(phase: DownloadPhase.importing));
      final summary = await ref
          .read(importerProvider)
          .importFiles(
            [named.path],
            sourceKeys: {named.path: job.result.sourceKey},
          );
      if (summary.added == 1) {
        await _deleteFolderNow(job.id);
        _set(job.id, (j) => j.copyWith(phase: DownloadPhase.done));
      } else if (summary.duplicates == 1) {
        await _deleteFolderNow(job.id);
        _set(
          job.id,
          (j) => j.copyWith(
            phase: DownloadPhase.duplicate,
            error: () => 'Already in your library',
          ),
        );
      } else {
        final reason = summary.failures.firstOrNull?.reason;
        throw OnlineError(reason ?? 'Could not be added');
      }
    } on DownloadCancelled {
      _set(job.id, (j) => j.copyWith(phase: DownloadPhase.cancelled));
    } on Object catch (e) {
      _set(
        job.id,
        (j) => j.copyWith(phase: DownloadPhase.failed, error: () => '$e'),
      );
    }
  }

  /// The cover for [result], or null if it cannot be fetched or decoded.
  Future<CoverBytes?> _cover(OnlineResult result) async {
    final url = result.coverUrl;
    if (url == null) return null;
    try {
      final body = await ref.read(httpTransportProvider).get(url);
      if (body.statusCode != 200) {
        body.stream.listen(null).cancel().ignore();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        bytes.add(chunk);
      }
      final data = bytes.takeBytes();
      final crop = !result.squareCover;
      return await Isolate.run(() => prepareCover(data, cropToSquare: crop));
    } on Object {
      return null;
    }
  }
}

final _unsafe = RegExp(r'[/\\:*?"<>|\x00-\x1f\x7f]');

/// "Artist - Title" (or the title alone) as a safe file name without
/// extension, at most 120 characters and 200 UTF-8 bytes.
String downloadFileName(TrackTags tags) {
  final artist = tags.artist?.trim() ?? '';
  final title = tags.title?.trim() ?? '';
  var name = [artist, title].where((s) => s.isNotEmpty).join(' - ');
  name = name.replaceAll(_unsafe, '_').trim();
  // At most 120 characters and 200 UTF-8 bytes (file systems allow 255
  // bytes), cut on whole characters.
  final kept = StringBuffer();
  var bytes = 0;
  var chars = 0;
  for (final rune in name.runes) {
    final char = String.fromCharCode(rune);
    final size = utf8.encode(char).length;
    if (chars == 120 || bytes + size > 200) break;
    kept.write(char);
    bytes += size;
    chars++;
  }
  name = kept.toString().trim();
  return name.isEmpty ? 'download' : name;
}

/// `<temporary dir>/owntune-download`, where jobs keep their files until the
/// import. Its own name: on Linux the temporary dir is the shared `/tmp`.
Future<Directory> defaultDownloadDir({
  Future<Directory> Function() temp = getTemporaryDirectory,
}) async => Directory(p.join((await temp()).path, 'owntune-download'));

/// Empties the download folder (leftovers of a killed app). Never throws.
Future<void> cleanupDownloads(Directory dir) async {
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
  } on Object {
    // Best effort; the next start tries again.
  }
}
