import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/audio_engine.dart';
import 'package:owntune/player/play_queue.dart';

/// What the player shows: the queue and whether it is playing. The position
/// is a stream of its own ([playerPositionProvider]) so that it does not
/// rebuild everything several times a second.
class PlayerState {
  const PlayerState({this.queue = PlayQueue.empty, this.playing = false});

  final PlayQueue queue;
  final bool playing;
}

final playerProvider = NotifierProvider<PlayerController, PlayerState>(
  PlayerController.new,
);

/// The playback position of the loaded song.
final playerPositionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioEngineProvider).position,
);

/// The current song, resolved in the library so tag changes show up.
final currentTrackProvider = Provider<Track?>((ref) {
  final id = ref.watch(playerProvider.select((s) => s.queue.current?.trackId));
  if (id == null) return null;
  final tracks = ref.watch(tracksProvider).value ?? const [];
  for (final t in tracks) {
    if (t.id == id) return t;
  }
  return null;
});

/// After this long into a song, Previous restarts it instead of going back.
const _restartThreshold = Duration(seconds: 3);

/// Owns the queue and drives the [AudioEngine], one file at a time.
///
/// It stores track ids and follows [tracksProvider]: deleted songs leave the
/// queue, and if the current one goes, playback moves on.
class PlayerController extends Notifier<PlayerState> {
  late AudioEngine _engine;
  final _notices = StreamController<String>.broadcast();
  var _tracks = <int, Track>{};
  var _position = Duration.zero;

  /// Bumped by every load; a load that finishes after a newer one started
  /// does nothing.
  var _generation = 0;

  /// Songs that failed in a row; reset by a successful load.
  var _failures = 0;

  Stream<String> get notices => _notices.stream;

  PlayQueue get _queue => state.queue;

  @override
  PlayerState build() {
    _engine = ref.watch(audioEngineProvider);
    final subs = [
      _engine.position.listen((p) => _position = p),
      _engine.completed.listen((_) => _onCompleted()),
      _engine.errors.listen((_) => _onFailure(_queue, play: true)),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    // Not fireImmediately: _onTracks reads `state`, which does not exist
    // until build returns.
    _tracks = _byId(ref.read(tracksProvider).value ?? const []);
    ref.listen(tracksProvider, (_, next) {
      final tracks = next.value;
      if (tracks != null) _onTracks(tracks);
    });
    return const PlayerState();
  }

  /// Plays [tracks] from [start]; the list becomes the queue.
  Future<void> playList(
    List<Track> tracks, {
    required int start,
    required String source,
  }) => _start(
    PlayQueue.of(
      [for (final t in tracks) t.id],
      start: start,
      source: source,
      repeat: _queue.repeat,
    ),
    play: true,
  );

  Future<void> togglePlay() async {
    if (_queue.isEmpty) return;
    if (state.playing) {
      state = PlayerState(queue: _queue);
      await _engine.pause();
    } else {
      state = PlayerState(queue: _queue, playing: true);
      await _engine.play();
    }
  }

  Future<void> next() async {
    if (!_queue.hasNext) return;
    await _start(
      _queue.withIndex(_queue.nextIndex(auto: false)!),
      play: state.playing,
    );
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    final previous = _queue.previousIndex;
    if (previous == null || _position > _restartThreshold) {
      await seek(Duration.zero);
    } else {
      await _start(_queue.withIndex(previous), play: state.playing);
    }
  }

  /// The previous song regardless of the position (swipe on the mini
  /// player); on the first song it restarts it.
  Future<void> skipBack() async {
    if (_queue.isEmpty) return;
    final previous = _queue.previousIndex;
    if (previous == null) {
      await seek(Duration.zero);
    } else {
      await _start(_queue.withIndex(previous), play: state.playing);
    }
  }

  Future<void> seek(Duration position) async {
    _position = position;
    await _engine.seek(position);
  }

  void cycleRepeat() => _set(_queue.withRepeat(_queue.repeat.next));

  Future<void> playNext(Track t) => _add(t, next: true);

  Future<void> playLater(Track t) => _add(t, next: false);

  Future<void> jumpTo(int key) => _start(_queue.jumpTo(key), play: true);

  void moveUpcoming(int from, int to) => _set(_queue.moveUpcoming(from, to));

  Future<void> remove(int key) async => _set(_queue.remove(key));

  void clearUpcoming() => _set(_queue.clearUpcoming());

  void _set(PlayQueue queue) =>
      state = PlayerState(queue: queue, playing: state.playing);

  Future<void> _add(Track t, {required bool next}) async {
    if (_queue.isEmpty) {
      await _start(
        PlayQueue(repeat: _queue.repeat).insertNext(t.id),
        play: true,
      );
      return;
    }
    _set(next ? _queue.insertNext(t.id) : _queue.append(t.id));
  }

  /// Loads the current entry of [queue] and plays it if [play].
  Future<void> _start(PlayQueue queue, {required bool play}) async {
    final generation = ++_generation;
    final entry = queue.current;
    if (entry == null) {
      await _stop();
      return;
    }
    state = PlayerState(queue: queue, playing: play);
    _position = Duration.zero;
    final track = _tracks[entry.trackId];
    try {
      if (track == null) throw StateError('track ${entry.trackId} is gone');
      await _engine.load(ref.read(storageProvider).audioFile(track.fileName));
    } on Object {
      if (generation != _generation) return;
      await _onFailure(queue, play: play);
      return;
    }
    if (generation != _generation) return;
    _failures = 0;
    if (play) await _engine.play();
  }

  /// The current entry of [queue] could not be played: tell the user and
  /// try the following one, until every entry failed in a row.
  Future<void> _onFailure(PlayQueue queue, {required bool play}) async {
    final entry = queue.current;
    if (entry == null) return;
    final track = _tracks[entry.trackId];
    _notices.add(
      "Couldn't play “${track == null ? 'song' : displayTitle(track.title, track.originalName)}”",
    );
    _failures++;
    final next = queue.nextIndex(auto: false);
    if (next == null || _failures >= queue.entries.length) {
      _failures = 0;
      await _stop();
      return;
    }
    await _start(queue.withIndex(next), play: play);
  }

  Future<void> _onCompleted() async {
    final entry = _queue.current;
    if (entry == null) return;
    unawaited(
      ref
          .read(trackRepositoryProvider)
          .markPlayed(entry.trackId)
          .catchError(
            (Object _) {}, // a lost play count is not worth bothering the user
          ),
    );
    final next = _queue.nextIndex(auto: true);
    if (next == null) {
      state = PlayerState(queue: _queue);
      await _engine.pause();
      await seek(Duration.zero);
      return;
    }
    await _start(_queue.withIndex(next), play: true);
  }

  static Map<int, Track> _byId(List<Track> tracks) => {
    for (final t in tracks) t.id: t,
  };

  void _onTracks(List<Track> tracks) {
    _tracks = _byId(tracks);
    if (_queue.isEmpty) return;
    final ids = _tracks.keys.toSet();
    final followed = _queue.upcoming.any((e) => ids.contains(e.trackId));
    final (:queue, :currentRemoved) = _queue.retain(ids);
    if (!currentRemoved) {
      _set(queue);
    } else if (queue.isEmpty) {
      unawaited(_stop());
    } else {
      unawaited(_start(queue, play: followed && state.playing));
    }
  }

  Future<void> _stop() async {
    ++_generation;
    state = PlayerState(queue: PlayQueue(repeat: _queue.repeat));
    _position = Duration.zero;
    await _engine.unload();
  }
}
