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
/// The job's folder is deleted in every outcome.
class DownloadController extends Notifier<List<DownloadJob>> {
  var _nextId = 1;
  var _running = false;
  int? _runningId;
  CancelToken? _cancel;
  final _random = Random.secure();

  @override
  List<DownloadJob> build() => const [];

  /// Queues [result] with the confirmed [tags]. Does nothing while a job for
  /// the same song is waiting or running.
  void enqueue(OnlineResult result, TrackTags tags) {
    if (state.any(
      (j) => j.isActive && j.result.sourceKey == result.sourceKey,
    )) {
      return;
    }
    state = [...state, DownloadJob(id: _nextId++, result: result, tags: tags)];
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

  /// Drops every job that is no longer waiting or running.
  void clearFinished() => state = [
    for (final j in state)
      if (j.isActive) j,
  ];

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
    Directory? folder;
    try {
      _set(job.id, (j) => j.copyWith(phase: DownloadPhase.downloading));
      final source = ref.read(onlineSourcesProvider)[job.result.source]!;
      final stream = await source.resolve(job.result);
      if (cancel.isCancelled) throw DownloadCancelled();

      final root = await ref.read(downloadDirProvider)();
      folder = Directory(
        p.join(root.path, '${job.id}-${_random.nextInt(1 << 32)}'),
      );
      await folder.create(recursive: true);
      final part = File(p.join(folder.path, 'audio.part.${stream.extension}'));
      _set(job.id, (j) => j.copyWith(total: stream.contentLength));
      var percent = -1;
      await downloadStream(
        ref.read(httpTransportProvider),
        stream,
        part,
        cancel: cancel,
        onProgress: (received, total) {
          final now = received * 100 ~/ total;
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
        _set(job.id, (j) => j.copyWith(phase: DownloadPhase.done));
      } else if (summary.duplicates == 1) {
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
    } finally {
      try {
        await folder?.delete(recursive: true);
      } on Object {
        // Startup empties the download folder anyway.
      }
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
