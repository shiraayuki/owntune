import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

/// Plays one file at a time. The queue lives in `PlayerController`; this is
/// the small platform part behind it, so tests can use a fake.
abstract interface class AudioEngine {
  /// Loads [file] paused at 0. Throws if it cannot be opened or decoded.
  Future<void> load(File file);

  /// Starts playback and returns once it has started, not when it ends.
  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// Stops and releases the current file.
  Future<void> unload();

  Stream<Duration> get position;

  /// Fires when the loaded file played to its end.
  Stream<void> get completed;

  /// Errors after a successful load (e.g. a decoder error mid-file).
  Stream<Object> get errors;

  Future<void> dispose();
}

/// [AudioEngine] on just_audio (media_kit on Linux, see `initAudio`).
class JustAudioEngine implements AudioEngine {
  JustAudioEngine() {
    // just_audio reports some errors as stream errors and others (media_kit
    // on Linux) only as an event carrying an error code.
    _events = _player.playbackEventStream.listen((e) {
      final code = e.errorCode;
      if (code != null) {
        _onError(
          PlayerException(code, e.errorMessage, e.currentIndex),
          StackTrace.current,
        );
      }
    }, onError: _onError);
  }

  final _player = AudioPlayer();
  final _errors = StreamController<Object>.broadcast();
  late final StreamSubscription<PlaybackEvent> _events;

  /// Set while [load] runs; errors then fail the load instead of being
  /// reported on [errors].
  Completer<void>? _loading;

  void _onError(Object e, StackTrace _) {
    final loading = _loading;
    if (loading != null) {
      if (!loading.isCompleted) loading.completeError(e);
    } else {
      _errors.add(e);
    }
  }

  @override
  Future<void> load(File file) async {
    final loading = _loading = Completer<void>();
    // media_kit (Linux) reports an unreadable file only as an error event
    // and never completes setFilePath, so the load also ends on the first
    // error. A later load interrupts the abandoned call; ignore that.
    final open = _player.setFilePath(file.path);
    open
        .then(
          (_) {
            if (!loading.isCompleted) loading.complete();
          },
          onError: (Object e, StackTrace s) {
            if (!loading.isCompleted) loading.completeError(e, s);
          },
        )
        .ignore();
    try {
      await loading.future;
    } finally {
      if (identical(_loading, loading)) _loading = null;
    }
  }

  @override
  Future<void> play() async {
    // AudioPlayer.play() completes only when playback stops again.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> unload() => _player.stop();

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<void> get completed => _player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) {});

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  Future<void> dispose() async {
    await _events.cancel();
    await _errors.close();
    await _player.dispose();
  }
}
