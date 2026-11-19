import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/audio_engine.dart';
import 'package:owntune/player/play_queue.dart';
import 'package:owntune/player/player_snapshot.dart';
import 'package:owntune/player/shuffle.dart';

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

/// The randomness behind shuffle; tests override it with a seeded one.
final randomProvider = Provider<Random>((ref) => Random());

/// After this long into a song, Previous restarts it instead of going back.
const _restartThreshold = Duration(seconds: 3);

/// While playing, the position is saved this often.
const _saveEvery = Duration(seconds: 5);

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

  /// The saved state of the last run, until the first library snapshot
  /// lets it be restored.
  PlayerSnapshot? _pendingRestore;

  /// What was saved last: queue signature and position.
  String? _savedQueue;
  var _savedPosition = Duration.zero;

  Stream<String> get notices => _notices.stream;

  PlayQueue get _queue => state.queue;

  @override
  PlayerState build() {
    _engine = ref.watch(audioEngineProvider);
    final subs = [
      _engine.position.listen(_onPosition),
      _engine.playingChanges.listen(_onEnginePlaying),
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
    final initial = ref.read(tracksProvider).value;
    _tracks = _byId(initial ?? const []);
    _pendingRestore = ref.read(initialPlayerSnapshotProvider);
    if (initial != null && _pendingRestore != null) {
      Future.microtask(_restoreIfPending);
    }
    listenSelf((_, next) => _saveQueueIfChanged(next));
    ref.listen(tracksProvider, (_, next) {
      final tracks = next.value;
      if (tracks != null) _onTracks(tracks);
    });
    return const PlayerState();
  }

  /// Plays [tracks] from [start]; the list becomes the queue.
  ///
  /// [shuffle] null keeps the shuffle mode (when on, the tapped song plays
  /// first and the rest is shuffled); true turns it on and starts with a
  /// shuffled song ([start] is ignored); false turns it off.
  Future<void> playList(
    List<Track> tracks, {
    required int start,
    required String source,
    bool? shuffle,
  }) {
    var queue = PlayQueue.of(
      [for (final t in tracks) t.id],
      start: start,
      source: source,
      repeat: _queue.repeat,
    );
    if (shuffle ?? _queue.shuffled) {
      queue = queue.shuffleOn(_spread, keepCurrent: shuffle != true);
    }
    return _start(queue, play: true);
  }

  /// Shuffle on or off; the current song keeps playing.
  void toggleShuffle() =>
      _set(_queue.shuffled ? _queue.shuffleOff() : _queue.shuffleOn(_spread));

  /// Spreads entries by artist and album as the library groups them.
  List<QueueEntry> _spread(List<QueueEntry> entries) => spread(
    entries,
    artist: (e) {
      final t = _tracks[e.trackId];
      return t == null ? null : artistGroupKey(t.artist);
    },
    album: (e) {
      final t = _tracks[e.trackId];
      return t == null ? null : albumKeyOf(t);
    },
    random: ref.read(randomProvider),
  );

  /// An empty queue that keeps the repeat and shuffle modes.
  PlayQueue get _emptyQueue => PlayQueue(
    repeat: _queue.repeat,
    original: _queue.shuffled ? const [] : null,
  );

  Future<void> togglePlay() async {
    if (_queue.isEmpty) return;
    if (state.playing) {
      state = PlayerState(queue: _queue);
      await _engine.pause();
      _save();
    } else {
      state = PlayerState(queue: _queue, playing: true);
      await _engine.play();
    }
  }

  Future<void> next() async {
    if (!_queue.hasNext) return;
    await _start(
      _queue.following(auto: false, spread: _spread)!,
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
    _save();
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
      await _start(_emptyQueue.insertNext(t.id), play: true);
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
    // just_audio keeps playing into a newly loaded file.
    if (!play) await _engine.pause();
    if (generation != _generation) return;
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
    // Skips keep the order (no reshuffle on wrapping), so counting failures
    // up to the queue length means every entry was tried once.
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
    final next = _queue.following(auto: true, spread: _spread);
    if (next == null) {
      state = PlayerState(queue: _queue);
      await _engine.pause();
      await seek(Duration.zero);
      return;
    }
    await _start(next, play: true);
  }

  /// The engine changed its play state, possibly on its own (a call, a
  /// system pause); the player state follows it.
  void _onEnginePlaying(bool playing) {
    if (_queue.isEmpty || playing == state.playing) return;
    state = PlayerState(queue: _queue, playing: playing);
  }

  /// Brings back the saved player, paused at its position. Songs deleted
  /// since are dropped like any deletion.
  Future<void> _restoreIfPending() async {
    final saved = _pendingRestore;
    _pendingRestore = null;
    if (saved == null || !_queue.isEmpty) return;
    final (:queue, :currentRemoved) = PlayQueue.of(
      saved.trackIds,
      start: saved.index,
      source: saved.source,
      repeat: saved.repeat,
      originalOrder: saved.shuffleOrder,
    ).retain(_tracks.keys.toSet());
    if (queue.isEmpty) {
      _save();
      return;
    }
    await _start(queue, play: false);
    if (!currentRemoved && _queue.current == queue.current) {
      await seek(saved.position);
    }
  }

  void _onPosition(Duration p) {
    _position = p;
    if (state.playing && (p - _savedPosition).abs() >= _saveEvery) _save();
  }

  /// Saves when the queue, its index, source, repeat or shuffle changed.
  void _saveQueueIfChanged(PlayerState next) {
    final q = next.queue;
    final signature = [
      for (final e in q.entries) e.key,
      '|',
      q.index,
      q.source,
      q.repeat.name,
      '|',
      ...?q.original?.map((e) => e.key),
      q.shuffled,
    ].join(',');
    if (signature == _savedQueue) return;
    _savedQueue = signature;
    _save();
  }

  /// Best effort: a failed save only costs the restore.
  void _save() {
    _savedPosition = _position;
    final q = _queue;
    final snapshot = q.isEmpty
        ? null
        : PlayerSnapshot(
            trackIds: [for (final e in q.entries) e.trackId],
            index: q.index,
            source: q.source,
            repeat: q.repeat,
            position: _position,
            shuffleOrder: _shuffleOrder(q),
          );
    unawaited(
      ref
          .read(playerStateStoreProvider)
          .save(snapshot)
          .catchError((Object _) {}),
    );
  }

  /// Positions of [q]'s unshuffled order in its entries; null unshuffled.
  static List<int>? _shuffleOrder(PlayQueue q) {
    final original = q.original;
    if (original == null) return null;
    final at = {for (final (i, e) in q.entries.indexed) e.key: i};
    return [for (final e in original) at[e.key]!];
  }

  static Map<int, Track> _byId(List<Track> tracks) => {
    for (final t in tracks) t.id: t,
  };

  void _onTracks(List<Track> tracks) {
    _tracks = _byId(tracks);
    if (_pendingRestore != null) {
      _restoreIfPending();
      return;
    }
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
    state = PlayerState(queue: _emptyQueue);
    _position = Duration.zero;
    await _engine.unload();
  }
}
