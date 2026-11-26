import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/audio_engine.dart';
import 'package:owntune/player/listen_session.dart';
import 'package:owntune/player/normalization.dart';
import 'package:owntune/player/play_queue.dart';
import 'package:owntune/player/queue_source.dart';
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

/// How close to its stored length a song counts as at its end, for the
/// stall watch (see `_endStall`).
const _endMargin = Duration(seconds: 1);

/// How far past its length a download may play before it counts as ended
/// (see `_watchEnd`).
const _downloadOverrun = Duration(seconds: 1);

/// Resuming after a pause at least this long starts a new listen session.
const _longPause = Duration(minutes: 30);

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

  /// Whether the current entry's file finished loading; positions before
  /// that may still come from the previous file.
  var _loaded = false;

  /// Fires when the position stands still at the end of a playing song: iOS
  /// does not always report the end (with a downloaded, fragmented MP4 the
  /// AVPlayer can stop at the last position without its end notification,
  /// and just_audio ignores the stall signals), so the player moves on by
  /// itself. A position that keeps moving re-arms it, so a song whose stored
  /// length is too short is never cut.
  Timer? _endStall;
  Duration? _stallPosition;

  /// The load generation whose end was handled, so a late end report after
  /// the stall timer (or the other way round) does not skip a song.
  int? _endedGeneration;

  /// What has been heard of the current entry, and the key of that entry.
  ListenSession? _session;
  int? _sessionKey;

  /// When playback was paused, to tell a long pause from a short one.
  DateTime? _pausedAt;

  /// True during the pause between two songs, so the engine's report of it
  /// is not taken for a pause by the system.
  var _advancing = false;

  /// History writes, one after another: an update never overtakes the
  /// insert that gives it its row id.
  Future<void> _writes = Future.value();

  /// The loudness of the loaded song, read when it was loaded.
  double? _currentLufs;

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
      _endStall?.cancel();
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
    ref.listen(
      settingsProvider.select((s) => s.normalizeVolume),
      (_, _) => unawaited(_applyVolume()),
    );
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
    required QueueSource source,
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

  /// Reloads the current song at its position if its id is in [trackIds].
  /// After an edit its file was replaced, and the engine may still read the
  /// old one.
  Future<void> reloadIfCurrent(Set<int> trackIds) async {
    final current = _queue.current;
    if (current == null || !trackIds.contains(current.trackId)) return;
    final position = _position;
    await _start(_queue, play: state.playing, keepSession: true);
    if (_queue.current == current) await seek(position);
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
      _pausedAt = _now();
      state = PlayerState(queue: _queue);
      await _engine.pause();
      _save();
    } else {
      _onResume();
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
    _session?.resetBaseline(position);
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
  ///
  /// The entry gets a new listen session, unless [keepSession] and it is
  /// the entry the current session belongs to (a reload of the same song).
  Future<void> _start(
    PlayQueue queue, {
    required bool play,
    bool keepSession = false,
  }) async {
    final generation = ++_generation;
    final entry = queue.current;
    if (entry == null) {
      await _stop();
      return;
    }
    _loaded = false;
    _endStall?.cancel();
    _endStall = null;
    // A reload of the same song (after Edit Info) keeps its volume, so a
    // measurement that arrived meanwhile never changes it mid-song.
    final sameSong =
        keepSession && _session != null && _sessionKey == entry.key;
    if (!keepSession || _session == null || _sessionKey != entry.key) {
      _endSession();
      _beginSession(queue);
    }
    if (play) _pausedAt = null;
    state = PlayerState(queue: queue, playing: play);
    _position = Duration.zero;
    // just_audio keeps playing into a newly loaded file.
    if (!play) await _engine.pause();
    if (generation != _generation) return;
    final track = _tracks[entry.trackId];
    // The volume is set before the load: a playing engine starts the new
    // file as soon as it is loaded, and it must not start at the old level.
    if (!sameSong) {
      final lufs = track == null ? null : await _lufsOf(track.id);
      if (generation != _generation) return;
      _currentLufs = lufs;
    }
    await _applyVolume();
    if (generation != _generation) return;
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
    _loaded = true;
    _session?.resetBaseline(Duration.zero);
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
    // A completion during a load belongs to the song that was replaced.
    if (!_loaded) return;
    if (_endedGeneration == _generation) return;
    _endedGeneration = _generation;
    _endStall?.cancel();
    _endStall = null;
    final session = _session;
    if (session != null && session.complete()) _markPlayed(session.trackId);
    _endSession();
    // just_audio still counts as playing after the end, so its play() would
    // do nothing and the next song depended on the native player resuming
    // on its own, which iOS did not do. Pausing first gives the next song a
    // real play request once it is loaded. The player state stays playing
    // meanwhile, so the system controls do not flicker to paused.
    final generation = _generation;
    _advancing = true;
    await _engine.pause();
    // just_audio reports the pause before its future completes; should no
    // report come (the engine was paused already), the flag must not
    // swallow a later pause by the system.
    _advancing = false;
    if (generation != _generation) return;
    // Read after the pause: Play Next, repeat and the like may have changed
    // the queue meanwhile.
    final next = _queue.following(auto: true, spread: _spread);
    if (next == null) {
      // Played again from the start, the last song is a new listen.
      state = PlayerState(queue: _queue);
      _beginSession(_queue);
      await seek(Duration.zero);
      // The same load plays again: its next end counts again.
      _endedGeneration = null;
      return;
    }
    await _start(next, play: true);
  }

  /// The engine changed its play state, possibly on its own (a call, a
  /// system pause); the player state follows it.
  void _onEnginePlaying(bool playing) {
    if (_advancing) {
      // The pause between two songs is the controller's own.
      _advancing = false;
      if (!playing) return;
    }
    if (_queue.isEmpty || playing == state.playing) return;
    if (playing) {
      _onResume();
    } else {
      _pausedAt = _now();
      _writeSession(_session);
    }
    state = PlayerState(queue: _queue, playing: playing);
  }

  DateTime _now() => ref.read(clockProvider)();

  /// Starts a session for the current entry of [queue]; Play Next / Later
  /// entries are recorded as queued, a queue without a source as other.
  void _beginSession(PlayQueue queue) {
    final entry = queue.current;
    final track = entry == null ? null : _tracks[entry.trackId];
    if (entry == null || track == null) {
      _session = null;
      _sessionKey = null;
      return;
    }
    final source = entry.queued ? null : queue.source;
    _session = ListenSession(
      trackId: track.id,
      durationMs: track.durationMs,
      sourceKind: entry.queued
          ? QueueSourceKind.queued
          : source?.kind ?? QueueSourceKind.other,
      sourceKey: source?.key,
    )..resetBaseline(_position);
    _sessionKey = entry.key;
  }

  /// Writes the current session one last time and lets it go.
  void _endSession() {
    _writeSession(_session);
    _session = null;
    _sessionKey = null;
  }

  /// Playback resumes: after a long pause, what follows is a new listen of
  /// the same entry, from the current position.
  void _onResume() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null || _session?.startedAt == null) return;
    if (_now().difference(pausedAt) < _longPause) return;
    _endSession();
    _beginSession(_queue);
  }

  void _markPlayed(int trackId) => unawaited(
    Future.sync(() => ref.read(trackRepositoryProvider).markPlayed(trackId))
        .catchError(
          (Object _) {}, // a lost play count is not worth bothering the user
        ),
  );

  /// Queues a write of [session]'s row: inserted once it has 1 s heard,
  /// updated after that. Never awaited by playback; errors are swallowed.
  void _writeSession(ListenSession? session) {
    if (session == null || session.listenedMs < 1000) return;
    _writes = _writes
        .then((_) async {
          final plays = ref.read(playRepositoryProvider);
          final rowId = session.rowId;
          if (rowId == null) {
            session.rowId = await plays.insert(
              trackId: session.trackId,
              startedAt: session.startedAt!,
              listenedMs: session.listenedMs,
              counted: session.counted,
              sourceKind: session.sourceKind.name,
              sourceKey: session.sourceKey,
            );
          } else {
            await plays.update(
              rowId,
              listenedMs: session.listenedMs,
              counted: session.counted,
            );
          }
        })
        .catchError((Object _) {}); // a lost history row must not stop play
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
      queuedPositions: saved.queuedPositions?.toSet() ?? const {},
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
    final session = _session;
    if (session != null && _loaded) {
      if (!state.playing) {
        session.resetBaseline(p);
      } else if (session.advance(p, _now())) {
        _markPlayed(session.trackId);
        _writeSession(session);
      }
    }
    if (state.playing && (p - _savedPosition).abs() >= _saveEvery) _save();
    _watchEnd(p);
  }

  /// Arms [_endStall] while a playing song is within a second of its end,
  /// again whenever the position moves. A download ends once its position
  /// passes its length: that length is exact (computed from the HLS
  /// playlist), while just_audio keeps counting the position up as long as
  /// the AVPlayer still "plays" past the end of a fragmented MP4, so the
  /// position never stands still there.
  void _watchEnd(Duration p) {
    final moved = p != _stallPosition;
    _stallPosition = p;
    final entry = _queue.current;
    final track = entry == null ? null : _tracks[entry.trackId];
    final atEnd =
        _loaded &&
        state.playing &&
        track != null &&
        track.durationMs > 0 &&
        p >= Duration(milliseconds: track.durationMs) - _endMargin;
    if (!atEnd) {
      _endStall?.cancel();
      _endStall = null;
      return;
    }
    final length = Duration(milliseconds: track.durationMs);
    if (track.sourceKey != null && p >= length + _downloadOverrun) {
      _endStall?.cancel();
      _endStall = null;
      unawaited(_onCompleted());
      return;
    }
    if (!moved && _endStall != null) return;
    _endStall?.cancel();
    final generation = _generation;
    _endStall = Timer(ref.read(endStallWaitProvider), () {
      _endStall = null;
      if (generation == _generation && _loaded && state.playing) {
        _onCompleted();
      }
    });
  }

  /// Saves when the queue, its index, source, repeat or shuffle changed.
  void _saveQueueIfChanged(PlayerState next) {
    final q = next.queue;
    final signature = [
      for (final e in q.entries) e.key,
      '|',
      q.index,
      q.source?.kind.name,
      q.source?.key,
      q.source?.label,
      q.repeat.name,
      '|',
      ...q.entries.map((e) => e.queued ? 'q' : 'n'),
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
    _writeSession(_session);
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
            queuedPositions: _queuedPositions(q),
          );
    unawaited(
      ref
          .read(playerStateStoreProvider)
          .save(snapshot)
          .catchError((Object _) {}),
    );
  }

  /// Positions of [q]'s queued entries; null when none is queued.
  static List<int>? _queuedPositions(PlayQueue q) {
    final positions = [
      for (final (i, e) in q.entries.indexed)
        if (e.queued) i,
    ];
    return positions.isEmpty ? null : positions;
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

  /// The measured loudness of [trackId]; null when unmeasured or on any
  /// error, so a lookup can never stop a song.
  Future<double?> _lufsOf(int trackId) async {
    try {
      return await ref.read(loudnessRepositoryProvider).lufsOf(trackId);
    } on Object {
      return null;
    }
  }

  /// Sets the volume for the loaded song. A measurement that arrives while
  /// it plays applies from the next load, so the level never jumps.
  /// Best effort: an engine error here must not keep a song from playing.
  Future<void> _applyVolume() async {
    try {
      await _engine.setVolume(
        normalizationGain(
          _currentLufs,
          enabled: ref.read(settingsProvider).normalizeVolume,
        ),
      );
    } on Object {
      // Keeps the previous volume.
    }
  }

  Future<void> _stop() async {
    ++_generation;
    _currentLufs = null;
    _endSession();
    _loaded = false;
    state = PlayerState(queue: _emptyQueue);
    _position = Duration.zero;
    await _engine.unload();
  }
}
