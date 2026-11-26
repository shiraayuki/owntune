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

  /// Sets the playback volume, 0.0–1.0; it stays across loads.
  Future<void> setVolume(double volume);

  /// Stops and releases the current file.
  Future<void> unload();

  Stream<Duration> get position;

  /// Play state changes, including those the system makes on its own
  /// (a phone call, another app taking the audio, headphones unplugged).
  Stream<bool> get playingChanges;

  /// Fires when the loaded file played to its end.
  Stream<void> get completed;

  /// Errors after a successful load (e.g. a decoder error mid-file).
  Stream<Object> get errors;

  Future<void> dispose();
}

/// The code just_audio uses for a load cut off by a newer one; not a
/// failure of any file.
const _interruptedCode = 10000000;

/// One running [JustAudioEngine.load].
class _Load {
  final done = Completer<void>();

  /// True once this load's own "loading" event without an error code was
  /// seen; error codes before it belong to an earlier file.
  var sawCleanLoading = false;

  void complete() {
    if (!done.isCompleted) done.complete();
  }

  void fail(Object e, [StackTrace? s]) {
    if (!done.isCompleted) done.completeError(e, s);
  }
}

/// [AudioEngine] on just_audio (media_kit on Linux, see `initAudio`).
///
/// `setFilePath` decides whether a load worked. The exception is media_kit,
/// which reports an unreadable file only as an event with an error code and
/// never completes `setFilePath`; with [loadEndsOnErrorEvent] (default: on
/// Linux) such an event also fails the load, but only after this load's own
/// clean "loading" event: just_audio carries an earlier error code over into
/// the first event of the next load.
class JustAudioEngine implements AudioEngine {
  JustAudioEngine({bool? loadEndsOnErrorEvent})
    : _loadEndsOnErrorEvent = loadEndsOnErrorEvent ?? Platform.isLinux {
    _events = _player.playbackEventStream.listen(
      _onEvent,
      onError: (Object _, StackTrace _) {}, // reported via errorStream
    );
    _playerErrors = _player.errorStream.listen(_onPlayerError);
  }

  final _player = AudioPlayer();
  final bool _loadEndsOnErrorEvent;
  final _errors = StreamController<Object>.broadcast();
  late final StreamSubscription<PlaybackEvent> _events;
  late final StreamSubscription<PlayerException> _playerErrors;

  /// Set while [load] runs.
  _Load? _loading;

  void _onEvent(PlaybackEvent e) {
    final loading = _loading;
    if (loading == null || !_loadEndsOnErrorEvent) return;
    final code = e.errorCode;
    if (code == null) {
      if (e.processingState == ProcessingState.loading) {
        loading.sawCleanLoading = true;
      }
    } else if (loading.sawCleanLoading && code != _interruptedCode) {
      loading.fail(PlayerException(code, e.errorMessage, e.currentIndex));
    }
  }

  /// Errors after a load (deduplicated by just_audio). While a load runs,
  /// its outcome is decided in [load] instead.
  void _onPlayerError(PlayerException e) {
    if (_loading != null || e.code == _interruptedCode) return;
    _errors.add(e);
  }

  @override
  Future<void> load(File file) async {
    final loading = _loading = _Load();
    _player
        .setFilePath(file.path)
        .then((_) => loading.complete(), onError: loading.fail)
        .ignore();
    try {
      await loading.done.future;
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
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> unload() => _player.stop();

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<bool> get playingChanges => _player.playingStream.distinct();

  @override
  Stream<void> get completed => _player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) {});

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  Future<void> dispose() async {
    await _events.cancel();
    await _playerErrors.cancel();
    await _errors.close();
    await _player.dispose();
  }
}
