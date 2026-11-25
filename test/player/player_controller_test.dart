import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/player/play_queue.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/queue_source.dart';

import '../support/fakes.dart';

final a = track(1, title: 'A', durationMs: 240000);
final b = track(2, title: 'B', durationMs: 240000);
final c = track(3, title: 'C', durationMs: 240000);

void main() {
  late FakeAudioEngine engine;
  late FakeTrackRepository repo;
  late FakePlayRepository plays;
  late DateTime now;
  late StreamController<List<Track>> library;
  late ProviderContainer container;
  late List<String> notices;

  PlayerController player() => container.read(playerProvider.notifier);
  PlayerState state() => container.read(playerProvider);
  List<int> queueIds() => [for (final e in state().queue.entries) e.trackId];

  setUp(() async {
    engine = FakeAudioEngine();
    repo = FakeTrackRepository();
    plays = FakePlayRepository();
    now = DateTime(2026, 11, 24, 20);
    library = StreamController<List<Track>>();
    container = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        trackRepositoryProvider.overrideWithValue(repo),
        playRepositoryProvider.overrideWithValue(plays),
        clockProvider.overrideWithValue(() => now),
        storageProvider.overrideWithValue(
          LibraryStorage(Directory('/nonexistent/owntune')),
        ),
        tracksProvider.overrideWith((ref) => library.stream),
        playerStateStoreProvider.overrideWithValue(FakePlayerStateStore()),
      ],
    );
    container.listen(playerProvider, (_, _) {});
    container.listen(currentTrackProvider, (_, _) {});
    notices = [];
    final sub = player().notices.listen(notices.add);
    addTearDown(sub.cancel);
    library.add([a, b, c]);
    await pumpEventQueue();
  });

  tearDown(() async {
    container.dispose();
    await library.close();
  });

  Future<void> playAt(
    int start, {
    QueueSource source = const QueueSource.songs(),
  }) async {
    await player().playList([a, b, c], start: start, source: source);
    await pumpEventQueue();
  }

  test('playList loads and plays the tapped song', () async {
    await playAt(1);
    expect(engine.loaded, ['hash2.mp3']);
    expect(engine.playing, isTrue);
    expect(state().playing, isTrue);
    expect(state().queue.source, const QueueSource.songs());
    expect(container.read(currentTrackProvider)!.id, 2);
  });

  test('previous restarts after three seconds', () async {
    await playAt(1);
    engine.emitPosition(const Duration(seconds: 4));
    await pumpEventQueue();
    await player().previous();
    expect(engine.lastSeek, Duration.zero);
    expect(state().queue.index, 1);
  });

  test('previous goes back within the first three seconds', () async {
    await playAt(1);
    engine.emitPosition(const Duration(seconds: 2));
    await pumpEventQueue();
    await player().previous();
    await pumpEventQueue();
    expect(state().queue.index, 0);
    expect(engine.current, 'hash1.mp3');
    expect(engine.playing, isTrue);
  });

  test('previous on the first song restarts it', () async {
    await playAt(0);
    await player().previous();
    expect(engine.lastSeek, Duration.zero);
    expect(engine.loaded, ['hash1.mp3']);
  });

  test('next on the last song with repeat off does nothing', () async {
    await playAt(2);
    await player().next();
    await pumpEventQueue();
    expect(engine.loaded, ['hash3.mp3']);
    expect(state().queue.index, 2);
  });

  test('next keeps a paused player paused', () async {
    await playAt(0);
    await player().togglePlay();
    await player().next();
    await pumpEventQueue();
    expect(engine.current, 'hash2.mp3');
    expect(engine.playing, isFalse);
    expect(state().playing, isFalse);
  });

  test('a song that ends starts the next with its own play request', () async {
    // just_audio stays "playing" after the end, so a play() without the
    // pause would do nothing, and on iOS the next song stayed silent.
    await playAt(0);
    engine.calls.clear();
    engine.complete();
    await pumpEventQueue();
    expect(engine.calls, ['pause', 'load hash2.mp3', 'play']);
    expect(state().playing, isTrue);
    expect(state().queue.current!.trackId, 2);
  });

  test('the player never shows paused between two songs', () async {
    // The lock screen and the Android notification follow `playing`; a
    // pause there at every song change would flicker and, on Android, drop
    // the foreground service.
    await playAt(0);
    final seen = <bool>[];
    final sub = container.listen(
      playerProvider.select((s) => s.playing),
      (_, next) => seen.add(next),
    );
    addTearDown(sub.close);
    engine.complete();
    await pumpEventQueue();
    expect(seen, isNot(contains(false)));
    expect(engine.current, 'hash2.mp3');
    expect(engine.playing, isTrue);
  });

  test('a system pause after a song change is still followed', () async {
    await playAt(0);
    engine.complete();
    await pumpEventQueue();
    engine.emitPlaying(false);
    await pumpEventQueue();
    expect(state().playing, isFalse);
  });

  test('Play Next while the ended song pauses is kept', () async {
    await playAt(0);
    final hold = engine.holdPause = Completer<void>();
    engine.complete();
    await pumpEventQueue();
    await player().playNext(c);
    engine.holdPause = null;
    hold.complete();
    await pumpEventQueue();
    expect(state().queue.current!.trackId, 3);
    expect(engine.current, 'hash3.mp3');
    expect(queueIds(), [1, 3, 2, 3]);
  });

  test('repeat one replays with its own play request', () async {
    await playAt(0);
    player()
      ..cycleRepeat()
      ..cycleRepeat();
    engine.calls.clear();
    engine.complete();
    await pumpEventQueue();
    expect(engine.calls, ['pause', 'load hash1.mp3', 'play']);
  });

  test('end of queue pauses on the last song at zero', () async {
    await playAt(2);
    engine.complete();
    await pumpEventQueue();
    expect(state().playing, isFalse);
    expect(engine.playing, isFalse);
    expect(engine.lastSeek, Duration.zero);
    expect(state().queue.current!.trackId, 3);
    expect(container.read(currentTrackProvider)!.id, 3);
  });

  test('repeat all wraps after the last song', () async {
    await playAt(2);
    player().cycleRepeat();
    expect(state().queue.repeat, QueueRepeat.all);
    engine.complete();
    await pumpEventQueue();
    expect(engine.current, 'hash1.mp3');
    expect(engine.playing, isTrue);
  });

  test(
    'repeat one replays when the song ends but next still advances',
    () async {
      await playAt(0);
      player()
        ..cycleRepeat()
        ..cycleRepeat();
      expect(state().queue.repeat, QueueRepeat.one);
      engine.complete();
      await pumpEventQueue();
      expect(engine.loaded, ['hash1.mp3', 'hash1.mp3']);
      expect(engine.playing, isTrue);
      await player().next();
      await pumpEventQueue();
      expect(engine.current, 'hash2.mp3');
    },
  );

  test('a completion while the next song loads is stale', () async {
    final shortB = track(2, title: 'B', durationMs: 20000);
    library.add([a, shortB, c]);
    await pumpEventQueue();
    await player().playList(
      [a, shortB, c],
      start: 0,
      source: const QueueSource.songs(),
    );
    await pumpEventQueue();
    final hold = engine.holdLoad = Completer<void>();
    unawaited(player().next());
    await pumpEventQueue();
    // The end of A arrives after Next already switched to B.
    engine.complete();
    await pumpEventQueue();
    engine.holdLoad = null;
    hold.complete();
    await pumpEventQueue();
    expect(state().queue.current!.trackId, 2);
    expect(engine.current, 'hash2.mp3');
    expect(engine.playing, isTrue);
    expect(repo.played, isEmpty);
  });

  test('a long song that ends unheard does not count', () async {
    await playAt(0);
    engine.complete();
    await pumpEventQueue();
    expect(repo.played, isEmpty);
    await player().next();
    await pumpEventQueue();
    expect(repo.played, isEmpty);
    expect(plays.rows, isEmpty);
  });

  test('an unplayable song is skipped with a notice', () async {
    engine.failing.add('hash2.mp3');
    await playAt(1);
    expect(notices, ["Couldn't play “B”"]);
    expect(engine.current, 'hash3.mp3');
    expect(engine.playing, isTrue);
    expect(state().queue.current!.trackId, 3);
  });

  test('an error during playback skips to the next song', () async {
    await playAt(0);
    engine.emitError(StateError('decoder'));
    await pumpEventQueue();
    expect(notices, ["Couldn't play “A”"]);
    expect(engine.current, 'hash2.mp3');
  });

  test('stops when every song fails', () async {
    engine.failing.addAll({'hash1.mp3', 'hash2.mp3', 'hash3.mp3'});
    player().cycleRepeat(); // repeat all must not loop forever
    await playAt(0);
    expect(notices, hasLength(3));
    expect(state().queue.isEmpty, isTrue);
    expect(state().playing, isFalse);
    expect(container.read(currentTrackProvider), isNull);
  });

  test('deleting the current song moves on and keeps playing', () async {
    await playAt(0);
    library.add([b, c]);
    await pumpEventQueue();
    expect(engine.current, 'hash2.mp3');
    expect(engine.playing, isTrue);
    expect(queueIds(), [2, 3]);
  });

  test('deleting the current last song falls back paused', () async {
    await playAt(2);
    library.add([a, b]);
    await pumpEventQueue();
    expect(engine.current, 'hash2.mp3');
    expect(engine.playing, isFalse);
    expect(state().playing, isFalse);
  });

  test('deleting the last song left unloads', () async {
    await player().playList([a], start: 0, source: const QueueSource.songs());
    await pumpEventQueue();
    library.add([b, c]);
    await pumpEventQueue();
    expect(state().queue.isEmpty, isTrue);
    expect(engine.unloads, 1);
    expect(container.read(currentTrackProvider), isNull);
  });

  test('deleting an upcoming song only removes it', () async {
    await playAt(0);
    library.add([a, c]);
    await pumpEventQueue();
    expect(queueIds(), [1, 3]);
    expect(engine.loaded, ['hash1.mp3']);
  });

  test('play next with nothing loaded starts the song', () async {
    await player().playNext(b);
    await pumpEventQueue();
    expect(engine.current, 'hash2.mp3');
    expect(engine.playing, isTrue);
    expect(state().queue.source, isNull);
  });

  test('play next and play later add to a running queue', () async {
    await playAt(0);
    await player().playLater(a);
    await player().playNext(c);
    expect(queueIds(), [1, 3, 2, 3, 1]);
    expect(engine.loaded, ['hash1.mp3']);
  });

  test(
    'jumpTo, remove, moveUpcoming and clearUpcoming edit the queue',
    () async {
      await playAt(0);
      final entries = state().queue.entries;
      player().moveUpcoming(0, 1);
      expect(queueIds(), [1, 3, 2]);
      await player().remove(entries[2].key);
      expect(queueIds(), [1, 2]);
      await player().jumpTo(entries[1].key);
      await pumpEventQueue();
      expect(engine.current, 'hash2.mp3');
      player().clearUpcoming();
      expect(queueIds(), [1, 2]);
      expect(state().queue.current!.trackId, 2);
    },
  );

  test('an import while playing does not reload', () async {
    await playAt(0);
    library.add([a, b, c, track(4, title: 'D')]);
    await pumpEventQueue();
    expect(engine.loaded, ['hash1.mp3']);
    expect(engine.playing, isTrue);
    expect(queueIds(), [1, 2, 3]);
  });

  test('a stale load does not win', () async {
    final hold = engine.holdLoad = Completer<void>();
    unawaited(
      player().playList([a, b, c], start: 0, source: const QueueSource.songs()),
    );
    await pumpEventQueue();
    engine.holdLoad = null;
    await playAt(1);
    // The real engine interrupts the abandoned load, which then throws.
    engine.failing.add('hash1.mp3');
    hold.complete();
    await pumpEventQueue();
    expect(notices, isEmpty);
    expect(container.read(currentTrackProvider)!.id, 2);
    expect(engine.current, 'hash2.mp3');
    expect(engine.playing, isTrue);
  });

  test('togglePlay pauses and resumes', () async {
    await playAt(0);
    await player().togglePlay();
    expect(engine.playing, isFalse);
    expect(state().playing, isFalse);
    await player().togglePlay();
    expect(engine.playing, isTrue);
    expect(state().playing, isTrue);
  });

  test('builds when the library is loaded before the player', () async {
    final early = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        playRepositoryProvider.overrideWithValue(FakePlayRepository()),
        tracksProvider.overrideWith((ref) => Stream.value([a, b])),
        playerStateStoreProvider.overrideWithValue(FakePlayerStateStore()),
        storageProvider.overrideWithValue(
          LibraryStorage(Directory('/nonexistent/owntune')),
        ),
      ],
    );
    addTearDown(early.dispose);
    early.listen(tracksProvider, (_, _) {});
    await pumpEventQueue();
    expect(early.read(tracksProvider).value, hasLength(2));

    expect(early.read(playerProvider).queue.isEmpty, isTrue);
    await early
        .read(playerProvider.notifier)
        .playList([a, b], start: 1, source: const QueueSource.songs());
    expect(early.read(currentTrackProvider)!.id, 2);
  });

  test('skipBack goes to the previous song even late in a song', () async {
    await playAt(1);
    engine.emitPosition(const Duration(seconds: 30));
    await pumpEventQueue();
    await player().skipBack();
    await pumpEventQueue();
    expect(state().queue.index, 0);
    expect(engine.current, 'hash1.mp3');
  });

  test('skipBack on the first song restarts it', () async {
    await playAt(0);
    await player().skipBack();
    expect(engine.loaded, ['hash1.mp3']);
    expect(engine.lastSeek, Duration.zero);
  });

  test('a pause by the system shows in the player state', () async {
    await playAt(0);
    engine.emitPlaying(false);
    await pumpEventQueue();
    expect(state().playing, isFalse);
  });

  test('a resume by the system shows too', () async {
    await playAt(0);
    await player().togglePlay();
    engine.emitPlaying(true);
    await pumpEventQueue();
    expect(state().playing, isTrue);
  });

  group('shuffle', () {
    List<int> sorted(List<int> xs) => [...xs]..sort();

    test('toggle shuffle keeps the song playing', () async {
      await playAt(1);
      final loads = engine.loaded.length;
      player().toggleShuffle();
      await pumpEventQueue();
      expect(state().queue.shuffled, isTrue);
      expect(state().queue.current!.trackId, 2);
      expect(state().queue.index, 0);
      expect(sorted(queueIds()), [1, 2, 3]);
      expect(state().playing, isTrue);
      expect(engine.loaded.length, loads);
    });

    test('toggle twice restores the list order', () async {
      await playAt(1);
      player()
        ..toggleShuffle()
        ..toggleShuffle();
      await pumpEventQueue();
      expect(state().queue.shuffled, isFalse);
      expect(queueIds(), [1, 2, 3]);
      expect(state().queue.current!.trackId, 2);
    });

    test('tapping a song with shuffle on plays it first', () async {
      await playAt(0);
      player().toggleShuffle();
      await player().playList(
        [a, b, c],
        start: 2,
        source: const QueueSource.songs(),
      );
      await pumpEventQueue();
      expect(state().queue.shuffled, isTrue);
      expect(state().queue.current!.trackId, 3);
      expect(state().queue.index, 0);
      expect(sorted(queueIds()), [1, 2, 3]);
      expect(engine.loaded.last, 'hash3.mp3');
    });

    test('album Shuffle starts shuffled', () async {
      await player().playList(
        [a, b, c],
        start: 0,
        source: QueueSource.album((artist: 'x', title: 'y'), 'Album'),
        shuffle: true,
      );
      await pumpEventQueue();
      expect(state().queue.shuffled, isTrue);
      expect(state().queue.index, 0);
      expect(sorted(queueIds()), [1, 2, 3]);
      expect(state().playing, isTrue);
    });

    test('Play turns shuffle off', () async {
      await playAt(0);
      player().toggleShuffle();
      await player().playList(
        [a, b, c],
        start: 0,
        source: QueueSource.album((artist: 'x', title: 'y'), 'Album'),
        shuffle: false,
      );
      await pumpEventQueue();
      expect(state().queue.shuffled, isFalse);
      expect(queueIds(), [1, 2, 3]);
      expect(state().queue.current!.trackId, 1);
    });

    test('shuffle survives an emptied queue', () async {
      await playAt(0);
      player().toggleShuffle();
      library.add([]);
      await pumpEventQueue();
      expect(state().queue.isEmpty, isTrue);
      library.add([a, b, c]);
      await pumpEventQueue();
      await playAt(0);
      expect(state().queue.shuffled, isTrue);
    });

    test('next under repeat all reshuffles at the end', () async {
      await playAt(0);
      player()
        ..toggleShuffle()
        ..cycleRepeat();
      expect(state().queue.repeat, QueueRepeat.all);
      await player().next();
      await player().next();
      await pumpEventQueue();
      expect(state().queue.index, 2);
      final ended = state().queue.current;
      await player().next();
      await pumpEventQueue();
      expect(state().queue.index, 0);
      expect(state().queue.current, isNot(ended));
      expect(state().queue.shuffled, isTrue);
      expect(sorted(queueIds()), [1, 2, 3]);
    });
  });

  test('skipping broken songs under shuffle and repeat all reaches the '
      'playable one', () async {
    final six = [
      for (var i = 1; i <= 6; i++) track(i, title: 'S$i', artist: 'Artist $i'),
    ];
    library.add(six);
    await pumpEventQueue();
    for (var i = 2; i <= 6; i++) {
      engine.failing.add('hash$i.mp3');
    }
    player().cycleRepeat();
    // The order is random; several rounds make a wrap-around reshuffle
    // during the skips all but certain.
    for (var round = 0; round < 10; round++) {
      await player().playList(
        six,
        start: 0,
        source: const QueueSource.songs(),
        shuffle: true,
      );
      await pumpEventQueue();
      final order = [...state().queue.entries];
      final playable = order.indexWhere((e) => e.trackId == 1);
      if (playable == order.length - 1) continue; // no wrap from here
      // Start right after the playable song: the skips must wrap around.
      await player().jumpTo(order[playable + 1].key);
      await pumpEventQueue();
      expect(state().queue.current?.trackId, 1, reason: 'round $round');
      expect(state().queue.entries, order, reason: 'round $round');
    }
  });

  test('an edited current song is reloaded at its position', () async {
    await playAt(1);
    engine.emitPosition(const Duration(seconds: 40));
    await pumpEventQueue();
    await player().reloadIfCurrent({2, 3});
    await pumpEventQueue();
    expect(engine.loaded, ['hash2.mp3', 'hash2.mp3']);
    expect(engine.lastSeek, const Duration(seconds: 40));
    expect(engine.playing, isTrue);
    expect(state().queue.current!.trackId, 2);
  });

  test('editing other songs does not reload the current one', () async {
    await playAt(1);
    await player().reloadIfCurrent({1, 3});
    await pumpEventQueue();
    expect(engine.loaded, ['hash2.mp3']);
  });
  group('listens', () {
    /// Emits the positions [from] + 1 s … [to] seconds, one second apart.
    Future<void> hear(int from, int to) async {
      for (var s = from + 1; s <= to; s++) {
        engine.emitPosition(Duration(seconds: s));
        await pumpEventQueue();
      }
    }

    test('a 40 s listen counts once and writes one row', () async {
      await playAt(0);
      await hear(0, 29);
      expect(repo.played, isEmpty);
      await hear(29, 30);
      expect(repo.played, [1]);
      await hear(30, 40);
      expect(repo.played, [1]);
      await player().next();
      await pumpEventQueue();
      final row = plays.rows.values.single;
      expect(row.trackId, 1);
      expect(row.listenedMs, 40000);
      expect(row.counted, isTrue);
      expect(row.sourceKind, 'songs');
      expect(row.sourceKey, isNull);
      expect(row.startedAt, DateTime(2026, 11, 24, 20));
      expect(repo.played, [1]);
    });

    test('a skip at 10 s writes an uncounted row', () async {
      await playAt(0);
      await hear(0, 10);
      await player().next();
      await pumpEventQueue();
      expect(repo.played, isEmpty);
      final row = plays.rows.values.single;
      expect(row.listenedMs, 10000);
      expect(row.counted, isFalse);
    });

    test('under one second writes no row', () async {
      await playAt(0);
      engine.emitPosition(const Duration(milliseconds: 500));
      await pumpEventQueue();
      await player().next();
      await pumpEventQueue();
      expect(plays.rows, isEmpty);
      expect(repo.played, isEmpty);
    });

    test('a seek forward does not add time', () async {
      await playAt(0);
      await hear(0, 10);
      await player().seek(const Duration(seconds: 12));
      await hear(12, 14);
      await player().next();
      await pumpEventQueue();
      expect(plays.rows.values.single.listenedMs, 12000);
    });

    test('completion does not count twice', () async {
      await playAt(0);
      await hear(0, 40);
      engine.complete();
      await pumpEventQueue();
      expect(repo.played, [1]);
      final row = plays.rows.values.single;
      expect(row.listenedMs, 40000);
      expect(row.counted, isTrue);
    });

    test('a short song counts when it ends', () async {
      final short = track(1, title: 'A', durationMs: 20000);
      library.add([short, b, c]);
      await pumpEventQueue();
      await player().playList(
        [short, b, c],
        start: 0,
        source: const QueueSource.songs(),
      );
      await pumpEventQueue();
      await hear(0, 5);
      expect(repo.played, isEmpty);
      engine.complete();
      await pumpEventQueue();
      expect(repo.played, [1]);
      final row = plays.rows.values.single;
      expect(row.listenedMs, 5000);
      expect(row.counted, isTrue);
    });

    test('a short song that ends without being heard counts nothing', () async {
      final short = track(1, title: 'A', durationMs: 20000);
      library.add([short, b, c]);
      await pumpEventQueue();
      await player().playList(
        [short, b, c],
        start: 0,
        source: const QueueSource.songs(),
      );
      await pumpEventQueue();
      await player().seek(const Duration(seconds: 19));
      engine.complete();
      await pumpEventQueue();
      expect(repo.played, isEmpty);
      expect(plays.rows, isEmpty);
    });

    test('repeat one writes one row per round', () async {
      await playAt(0);
      player()
        ..cycleRepeat()
        ..cycleRepeat();
      expect(state().queue.repeat, QueueRepeat.one);
      await hear(0, 35);
      engine.complete();
      await pumpEventQueue();
      await hear(0, 35);
      engine.complete();
      await pumpEventQueue();
      expect(repo.played, [1, 1]);
      expect(plays.rows, hasLength(2));
      for (final row in plays.rows.values) {
        expect(row.trackId, 1);
        expect(row.listenedMs, 35000);
        expect(row.counted, isTrue);
      }
    });

    test('the same song queued twice gets a row per entry', () async {
      await player().playList(
        [a, a],
        start: 0,
        source: const QueueSource.songs(),
      );
      await pumpEventQueue();
      await hear(0, 31);
      await player().next();
      await pumpEventQueue();
      await hear(0, 12);
      await player().togglePlay();
      await pumpEventQueue();
      expect(repo.played, [1]);
      expect([for (final r in plays.rows.values) r.listenedMs], [31000, 12000]);
      expect([for (final r in plays.rows.values) r.counted], [true, false]);
    });

    test('a long pause starts a new session and resets the count', () async {
      await playAt(0);
      await hear(0, 25);
      await player().togglePlay();
      now = now.add(const Duration(minutes: 31));
      await player().togglePlay();
      await hear(25, 35);
      await player().next();
      await pumpEventQueue();
      expect(repo.played, isEmpty);
      final rows = plays.rows.values.toList();
      expect(rows, hasLength(2));
      expect(rows[0].listenedMs, 25000);
      expect(rows[0].counted, isFalse);
      expect(rows[0].startedAt, DateTime(2026, 11, 24, 20));
      expect(rows[1].listenedMs, 10000);
      expect(rows[1].counted, isFalse);
      expect(rows[1].startedAt, DateTime(2026, 11, 24, 20, 31));
    });

    test('a long pause by the system starts a new session too', () async {
      await playAt(0);
      await hear(0, 25);
      engine.emitPlaying(false);
      await pumpEventQueue();
      now = now.add(const Duration(hours: 8));
      engine.emitPlaying(true);
      await pumpEventQueue();
      await hear(25, 35);
      await player().next();
      await pumpEventQueue();
      expect([for (final r in plays.rows.values) r.listenedMs], [25000, 10000]);
    });

    test('a short pause keeps the session', () async {
      await playAt(0);
      await hear(0, 25);
      await player().togglePlay();
      now = now.add(const Duration(minutes: 5));
      await player().togglePlay();
      await hear(25, 35);
      await player().next();
      await pumpEventQueue();
      expect(repo.played, [1]);
      final row = plays.rows.values.single;
      expect(row.listenedMs, 35000);
      expect(row.counted, isTrue);
    });

    test('previous restarting the song keeps the session', () async {
      await playAt(0);
      await hear(0, 20);
      await player().previous();
      expect(engine.lastSeek, Duration.zero);
      await hear(0, 15);
      await player().next();
      await pumpEventQueue();
      expect(repo.played, [1]);
      final row = plays.rows.values.single;
      expect(row.listenedMs, 35000);
      expect(row.counted, isTrue);
    });

    test('a reload keeps the session', () async {
      await playAt(0);
      await hear(0, 20);
      await player().reloadIfCurrent({1});
      await pumpEventQueue();
      expect(engine.loaded, ['hash1.mp3', 'hash1.mp3']);
      await hear(20, 35);
      await player().next();
      await pumpEventQueue();
      expect(repo.played, [1]);
      final row = plays.rows.values.single;
      expect(row.listenedMs, 35000);
      expect(row.counted, isTrue);
    });

    test('a Play Next entry is recorded as queued', () async {
      await playAt(
        0,
        source: QueueSource.album((artist: 'x', title: 'y'), 'Album'),
      );
      await player().playNext(b);
      await player().next();
      await pumpEventQueue();
      await hear(0, 5);
      await player().next();
      await pumpEventQueue();
      final row = plays.rows.values.single;
      expect(row.trackId, 2);
      expect(row.sourceKind, 'queued');
      expect(row.sourceKey, isNull);
    });

    test('an album entry is recorded with its key', () async {
      await playAt(
        0,
        source: QueueSource.album((artist: 'x', title: 'y'), 'Album'),
      );
      await hear(0, 5);
      await player().next();
      await pumpEventQueue();
      final row = plays.rows.values.single;
      expect(row.sourceKind, 'album');
      expect(row.sourceKey, 'x\u0000y');
    });

    test('Play Later into an empty queue is recorded as queued', () async {
      await player().playLater(b);
      await pumpEventQueue();
      expect(state().queue.current!.queued, isTrue);
      await hear(0, 5);
      await player().togglePlay();
      await pumpEventQueue();
      expect(plays.rows.values.single.sourceKind, 'queued');
    });

    test('positions while paused add nothing', () async {
      await playAt(0);
      await hear(0, 5);
      await player().togglePlay();
      await hear(5, 10);
      await player().togglePlay();
      await hear(10, 12);
      await player().next();
      await pumpEventQueue();
      expect(plays.rows.values.single.listenedMs, 7000);
    });

    test('the row is written at the save points while playing', () async {
      await playAt(0);
      await hear(0, 6);
      expect(plays.rows.values.single.listenedMs, 5000);
      await hear(6, 12);
      expect(plays.rows.values.single.listenedMs, 10000);
      await player().togglePlay();
      await pumpEventQueue();
      expect(plays.rows.values.single.listenedMs, 12000);
    });

    test('deleting the last song ends its session', () async {
      await player().playList([a], start: 0, source: const QueueSource.songs());
      await pumpEventQueue();
      await hear(0, 3);
      library.add([b, c]);
      await pumpEventQueue();
      expect(state().queue.isEmpty, isTrue);
      expect(plays.rows.values.single.listenedMs, 3000);
    });

    test('a stale load does not end the new session', () async {
      final hold = engine.holdLoad = Completer<void>();
      unawaited(
        player().playList(
          [a, b, c],
          start: 0,
          source: const QueueSource.songs(),
        ),
      );
      await pumpEventQueue();
      engine.holdLoad = null;
      await playAt(1);
      engine.failing.add('hash1.mp3');
      hold.complete();
      await pumpEventQueue();
      await hear(0, 31);
      await player().next();
      await pumpEventQueue();
      final row = plays.rows.values.single;
      expect(row.trackId, 2);
      expect(row.listenedMs, 31000);
      expect(repo.played, [2]);
    });

    test('a failing play repository does not stop playback', () async {
      plays.error = StateError('disk full');
      await playAt(0);
      await hear(0, 40);
      await player().next();
      await pumpEventQueue();
      expect(engine.current, 'hash2.mp3');
      expect(engine.playing, isTrue);
      expect(notices, isEmpty);
      expect(repo.played, [1]);
      expect(plays.rows, isEmpty);
    });
  });
}
