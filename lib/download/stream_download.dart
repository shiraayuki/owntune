import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/mp4_duration.dart';

/// Lets the user stop a running download.
class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  final _whenCancelled = Completer<void>();

  bool get isCancelled => _cancelled;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _whenCancelled.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _whenCancelled.complete();
    for (final l in [..._listeners]) {
      l();
    }
  }

  void _listen(void Function() l) => _listeners.add(l);
  void _unlisten(void Function() l) => _listeners.remove(l);
}

/// Thrown when a [CancelToken] stopped the download.
class DownloadCancelled implements Exception {
  @override
  String toString() => 'Cancelled';
}

/// Downloads [stream] into [target]: a ranged stream in range requests of
/// [chunkBytes] (YouTube refuses or throttles a plain GET of the whole
/// file), an HLS stream as its init segment and then its media segments,
/// [parallel] of them requested at once.
///
/// After every completed chunk or segment a checkpoint is written to
/// `<target>.progress`. When it and [target] exist and describe the same
/// stream, the download continues after it instead of starting over (a
/// signed URL may have changed in between, the file it points to has not).
///
/// Fails with an [OnlineError] whose message says how far it got, or with
/// [DownloadCancelled]. [target] and the checkpoint are left as they are; the
/// caller deletes them or retries.
Future<void> downloadStream(
  HttpTransport http,
  ResolvedStream stream,
  File target, {
  required void Function(int received, int total) onProgress,
  required CancelToken cancel,
  int chunkBytes = 10 << 20,
  int parallel = 4,
}) => switch (stream) {
  RangedStream() => _downloadRanged(
    http,
    stream,
    target,
    onProgress: onProgress,
    cancel: cancel,
    chunkBytes: chunkBytes,
  ),
  SegmentedStream() => _downloadSegmented(
    http,
    stream,
    target,
    onProgress: onProgress,
    cancel: cancel,
    parallel: max(1, parallel),
  ),
};

/// Where a download stands: the length of the file, and how many chunks or
/// segments it holds (for a ranged one, the same as [bytes]).
typedef _Checkpoint = ({int bytes, int done});

File _checkpointFile(File target) => File('${target.path}.progress');

Future<void> _writeCheckpoint(File target, String shape, _Checkpoint at) =>
    _checkpointFile(
      target,
    ).writeAsString(jsonEncode({'shape': shape, ...at.toJson()}), flush: true);

extension on _Checkpoint {
  Map<String, int> toJson() => {'bytes': bytes, 'done': done};
}

/// The checkpoint to continue from, with [target] cut back to its length; or
/// null (after deleting both files) when the download starts over.
Future<_Checkpoint?> _resume(File target, String shape) async {
  final file = _checkpointFile(target);
  try {
    if (await file.exists() && await target.exists()) {
      final json = jsonDecode(await file.readAsString());
      if (json is Map &&
          json['shape'] == shape &&
          json['bytes'] is int &&
          json['done'] is int) {
        final at = (bytes: json['bytes'] as int, done: json['done'] as int);
        final length = await target.length();
        if (at.bytes > 0 && at.bytes <= length) {
          if (at.bytes < length) {
            final raf = await target.open(mode: FileMode.append);
            try {
              await raf.truncate(at.bytes);
            } finally {
              await raf.close();
            }
          }
          return at;
        }
      }
    }
  } on Object {
    // A broken checkpoint (or file) means starting over.
  }
  for (final f in [file, target]) {
    if (await f.exists()) await f.delete();
  }
  return null;
}

Future<void> _downloadRanged(
  HttpTransport http,
  RangedStream stream,
  File target, {
  required void Function(int received, int total) onProgress,
  required CancelToken cancel,
  required int chunkBytes,
}) async {
  final total = stream.contentLength;
  if (total <= 0) {
    throw const OnlineError("YouTube didn't say how big the file is");
  }
  final shape = 'ranged:$total';
  final resumed = await _resume(target, shape);
  final sink = target.openWrite(
    mode: resumed == null ? FileMode.write : FileMode.append,
  );
  var received = resumed?.bytes ?? 0;
  try {
    while (received < total) {
      if (cancel.isCancelled) throw DownloadCancelled();
      final end = min(received + chunkBytes, total) - 1;
      final url = stream.url.replace(
        queryParameters: {
          ...stream.url.queryParameters,
          'range': '$received-$end',
        },
      );
      final body = await http.get(url);
      if (body.statusCode != 200) {
        body.stream.listen(null).cancel().ignore();
        throw OnlineError(
          'Download failed: HTTP ${body.statusCode} after '
          '${_mb(received)} of ${_mb(total)} MB',
        );
      }
      final before = received;
      try {
        await _pipe(body.stream, cancel, (chunk) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        });
      } on DownloadCancelled {
        rethrow;
      } on Object {
        // The raw error names the signed URL (with the user's IP); say how
        // far it got instead.
        throw OnlineError(
          'Download stopped at ${_mb(received)} of ${_mb(total)} MB '
          '(connection lost)',
        );
      }
      if (received == before) {
        throw OnlineError(
          'Download stopped at ${_mb(received)} of ${_mb(total)} MB',
        );
      }
      await sink.flush();
      await _writeCheckpoint(target, shape, (bytes: received, done: received));
    }
  } finally {
    await sink.close();
  }
}

/// Why one segment request failed; [_SegmentFailure.status] is a non-200
/// answer, [lost] a broken connection and [empty] an answer without a body.
class _SegmentFailure implements Exception {
  const _SegmentFailure.status(int this.code) : empty = false;
  const _SegmentFailure.lost() : code = null, empty = false;
  const _SegmentFailure.empty() : code = null, empty = true;

  final int? code;
  final bool empty;
}

/// GETs [url] into memory. A cancel of [abort] ends it at once, whether the
/// server has answered or not.
Future<Uint8List> _fetchBytes(
  HttpTransport http,
  Uri url,
  CancelToken abort,
) async {
  final request = http.get(url);
  final HttpBody body;
  try {
    body = await Future.any([
      request,
      abort.whenCancelled.then<HttpBody>((_) => throw DownloadCancelled()),
    ]);
  } on DownloadCancelled {
    // The answer may still come; close it instead of leaving it open.
    request
        .then<void>(
          (b) => b.stream.listen(null).cancel().ignore(),
          onError: (Object _) {},
        )
        .ignore();
    rethrow;
  } on Object {
    throw const _SegmentFailure.lost();
  }
  if (body.statusCode != 200) {
    body.stream.listen(null).cancel().ignore();
    throw _SegmentFailure.status(body.statusCode);
  }
  final out = BytesBuilder();
  try {
    await _pipe(body.stream, abort, out.add);
  } on DownloadCancelled {
    rethrow;
  } on Object {
    throw const _SegmentFailure.lost();
  }
  if (out.isEmpty) throw const _SegmentFailure.empty();
  return out.takeBytes();
}

Future<void> _downloadSegmented(
  HttpTransport http,
  SegmentedStream stream,
  File target, {
  required void Function(int received, int total) onProgress,
  required CancelToken cancel,
  required int parallel,
}) async {
  final count = stream.segments.length;
  final estimate = stream.estimatedBytes;

  // Every request ends when [abort] does: on a cancel, and when this
  // function fails or returns, so that no request outlives it.
  final abort = CancelToken();
  void forwardCancel() => abort.cancel();
  cancel._listen(forwardCancel);
  if (cancel.isCancelled) forwardCancel();

  var received = 0;
  var done = 0;
  int totalNow() => done == 0 ? estimate : received * count ~/ done;

  /// Awaits [request]; its failures become the user's messages.
  Future<Uint8List> outcome(Future<Uint8List> request) async {
    try {
      return await request;
    } on _SegmentFailure catch (e) {
      final x = _mb(received);
      final y = _mb(totalNow());
      final code = e.code;
      throw OnlineError(
        code != null
            ? 'Download failed: HTTP $code after $x of $y MB'
            : e.empty
            ? 'Download stopped at $x of $y MB'
            : 'Download stopped at $x of $y MB (connection lost)',
      );
    }
  }

  IOSink? sink;
  try {
    // The shape needs the length of the patched init, so it comes first,
    // also when the download resumes.
    final init = patchMp4Duration(
      await outcome(_fetchBytes(http, stream.initUrl, abort)),
      stream.total,
    );
    if (cancel.isCancelled) throw DownloadCancelled();
    final shape = 'segmented:$count:${init.length}';
    final resumed = await _resume(target, shape);
    sink = target.openWrite(
      mode: resumed == null ? FileMode.write : FileMode.append,
    );
    if (resumed == null) {
      sink.add(init);
      await sink.flush();
      received = init.length;
      await _writeCheckpoint(target, shape, (bytes: received, done: 0));
      onProgress(received, estimate);
    } else {
      received = resumed.bytes;
      done = resumed.done;
      onProgress(received, totalNow());
    }

    // A sliding window of requests: segments are written strictly in order,
    // and a new request starts when the oldest one has been written.
    final window = Queue<Future<Uint8List>>();
    var next = done;
    while (done < count) {
      if (cancel.isCancelled) throw DownloadCancelled();
      while (window.length < parallel && next < count) {
        final request = _fetchBytes(http, stream.segments[next++].url, abort);
        request.ignore(); // Its error is raised when its turn comes.
        window.add(request);
      }
      final data = await outcome(window.removeFirst());
      // A cancel while waiting: nothing more may land in the file.
      if (cancel.isCancelled) throw DownloadCancelled();
      sink.add(data);
      await sink.flush();
      received += data.length;
      done++;
      await _writeCheckpoint(target, shape, (bytes: received, done: done));
      onProgress(received, totalNow());
    }
  } finally {
    abort.cancel();
    cancel._unlisten(forwardCancel);
    await sink?.close();
  }
}

/// Feeds [source] into [onData] until it ends; a cancel stops it at once,
/// even while the server sends nothing.
Future<void> _pipe(
  Stream<List<int>> source,
  CancelToken cancel,
  void Function(List<int>) onData,
) {
  final done = Completer<void>();
  late final StreamSubscription<List<int>> sub;
  void onCancel() {
    sub.cancel().ignore();
    if (!done.isCompleted) done.completeError(DownloadCancelled());
  }

  sub = source.listen(
    (chunk) {
      if (cancel.isCancelled) return onCancel();
      onData(chunk);
    },
    onError: (Object e, StackTrace s) {
      if (!done.isCompleted) done.completeError(e, s);
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );
  cancel._listen(onCancel);
  if (cancel.isCancelled) onCancel();
  return done.future.whenComplete(() => cancel._unlisten(onCancel));
}

String _mb(int bytes) => (bytes / (1 << 20)).toStringAsFixed(1);
