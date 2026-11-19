import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/player_controller.dart';

/// What the lock screen, Control Center or Android notification shows.
class NowPlaying {
  const NowPlaying({
    required this.track,
    this.coverFile,
    required this.playing,
    required this.position,
    required this.hasNext,
  });

  final Track track;
  final File? coverFile;
  final bool playing;
  final Duration position;
  final bool hasNext;
}

/// What the system controls can ask the player to do.
abstract interface class SystemCommands {
  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
}

/// The system's media controls (lock screen, Control Center, Android
/// notification). Kept behind this interface so widget tests and Linux run
/// without audio_service.
abstract interface class SystemControls {
  void connect(SystemCommands commands);

  /// Shows [now], or clears the controls for null.
  void show(NowPlaying? now);
}

/// No system controls (Linux, tests).
class NoSystemControls implements SystemControls {
  const NoSystemControls();

  @override
  void connect(SystemCommands commands) {}

  @override
  void show(NowPlaying? now) {}
}

/// [SystemControls] on audio_service (iOS, Android).
class AudioServiceControls implements SystemControls {
  AudioServiceControls._(this._handler);

  final _OwntuneAudioHandler _handler;
  int? _shownTrackId;
  String? _shownCover;

  static Future<AudioServiceControls> init() async {
    final handler = await AudioService.init(
      builder: _OwntuneAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.owntune.playback',
        androidNotificationChannelName: 'Playback',
      ),
    );
    return AudioServiceControls._(handler);
  }

  @override
  void connect(SystemCommands commands) => _handler.commands = commands;

  @override
  void show(NowPlaying? now) {
    if (now == null) {
      _shownTrackId = null;
      _shownCover = null;
      _handler.mediaItem.add(null);
      _handler.playbackState.add(PlaybackState());
      return;
    }
    final t = now.track;
    final cover = now.coverFile?.path;
    // A new media item makes the system fetch the artwork again.
    if (t.id != _shownTrackId || cover != _shownCover) {
      _shownTrackId = t.id;
      _shownCover = cover;
      _handler.mediaItem.add(
        MediaItem(
          id: '${t.id}',
          title: displayTitle(t.title, t.originalName),
          artist: displayArtist(t.artist),
          album: t.album,
          duration: Duration(milliseconds: t.durationMs),
          artUri: cover == null ? null : Uri.file(cover),
        ),
      );
    }
    _handler.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          now.playing ? MediaControl.pause : MediaControl.play,
          if (now.hasNext) MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: [0, 1, if (now.hasNext) 2],
        processingState: AudioProcessingState.ready,
        playing: now.playing,
        updatePosition: now.position,
      ),
    );
  }
}

class _OwntuneAudioHandler extends BaseAudioHandler {
  SystemCommands? commands;

  @override
  Future<void> play() async => commands?.play();

  @override
  Future<void> pause() async => commands?.pause();

  @override
  Future<void> stop() async => commands?.pause();

  @override
  Future<void> skipToNext() async => commands?.next();

  @override
  Future<void> skipToPrevious() async => commands?.previous();

  @override
  Future<void> seek(Duration position) async => commands?.seek(position);
}

/// The system controls of this run; `main` overrides it with the instance
/// `startUp()` created.
final systemControlsProvider = Provider<SystemControls>(
  (ref) => const NoSystemControls(),
);

/// A position this far from where steady playback would be counts as a
/// jump (a seek), and is published again.
const _jump = Duration(seconds: 2);

/// Keeps the system controls in step with the player and sends their
/// commands to it. `OwntuneApp` keeps it alive.
final systemControlsSyncProvider = Provider<void>((ref) {
  final controls = ref.watch(systemControlsProvider);
  controls.connect(_PlayerCommands(ref));

  NowPlaying? last;
  final clock = Stopwatch()..start();

  void publish() {
    final track = ref.read(currentTrackProvider);
    if (track == null) {
      if (last != null) controls.show(null);
      last = null;
      return;
    }
    final player = ref.read(playerProvider);
    final cover = track.coverFile;
    last = NowPlaying(
      track: track,
      coverFile: cover == null
          ? null
          : ref.read(storageProvider).coverFile(cover),
      playing: player.playing,
      position: ref.read(playerPositionProvider).value ?? Duration.zero,
      hasNext: player.queue.hasNext,
    );
    clock.reset();
    controls.show(last);
  }

  ref.listen(currentTrackProvider, (_, _) => publish());
  ref.listen(
    playerProvider.select((s) => (s.playing, s.queue.hasNext)),
    (_, _) => publish(),
  );
  ref.listen(playerPositionProvider, (_, next) {
    final shown = last;
    final position = next.value;
    if (shown == null || position == null) return;
    final expected = shown.playing
        ? shown.position + clock.elapsed
        : shown.position;
    if ((position - expected).abs() > _jump) publish();
  });
  publish();
});

class _PlayerCommands implements SystemCommands {
  _PlayerCommands(this._ref);

  final Ref _ref;

  PlayerController get _player => _ref.read(playerProvider.notifier);

  bool get _playing => _ref.read(playerProvider).playing;

  @override
  Future<void> play() async {
    if (!_playing) await _player.togglePlay();
  }

  @override
  Future<void> pause() async {
    if (_playing) await _player.togglePlay();
  }

  @override
  Future<void> next() => _player.next();

  @override
  Future<void> previous() => _player.previous();

  @override
  Future<void> seek(Duration position) => _player.seek(position);
}
