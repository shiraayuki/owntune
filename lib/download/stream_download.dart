import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';

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

/// Downloads [stream] into [target] in range requests of [chunkBytes]
/// (YouTube refuses or throttles a plain GET of the whole file).
///
/// Fails with an [OnlineError] whose message says how far it got, or with
/// [DownloadCancelled]. [target] is left as it is; the caller deletes it.
Future<void> downloadStream(
  HttpTransport http,
  ResolvedStream stream,
  File target, {
  required void Function(int received, int total) onProgress,
  required CancelToken cancel,
  int chunkBytes = 10 << 20,
}) async {
  final total = stream.contentLength;
  if (total <= 0) {
    throw const OnlineError("YouTube didn't say how big the file is");
  }
  final sink = target.openWrite();
  var received = 0;
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
    }
  } finally {
    await sink.close();
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
