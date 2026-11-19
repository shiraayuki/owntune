import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/player/play_queue.dart';
import 'package:owntune/player/player_controller.dart';

import '../support/fakes.dart';

final a = track(1, title: 'A');
final b = track(2, title: 'B');
final c = track(3, title: 'C');

void main() {
  late FakeAudioEngine engine;
  late FakeTrackRepository repo;
  late StreamController<List<Track>> library;
  late ProviderContainer container;
  late List<String> notices;

  PlayerController player() => container.read(playerProvider.notifier);
  PlayerState state() => container.read(playerProvider);
  List<int> queueIds() => [for (final e in state().queue.entries) e.trackId];

  setUp(() async {
    engine = FakeAudioEngine();
    repo = FakeTrackRepository();
    library = StreamController<List<Track>>();
    container = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        trackRepositoryProvider.overrideWithValue(repo),
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

  Future<void> playAt(int start, {String source = 'Songs'}) async {
    await player().playList([a, b, c], start: start, source: source);
    await pumpEventQueue();
  }

  test('playList loads and plays the tapped song', () async {
    await playAt(1);
    expect(engine.loaded, ['hash2.mp3']);
    expect(engine.playing, isTrue);
    expect(state().playing, isTrue);
    expect(state().queue.source, 'Songs');
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

  test('a finished song counts as played, a skipped one does not', () async {
    await playAt(0);
    engine.complete();
    await pumpEventQueue();
    expect(repo.played, [1]);
    await player().next();
    await pumpEventQueue();
    expect(repo.played, [1]);
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
    await player().playList([a], start: 0, source: 'Songs');
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
    unawaited(player().playList([a, b, c], start: 0, source: 'Songs'));
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
        .playList([a, b], start: 1, source: 'Songs');
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
      await player().playList([a, b, c], start: 2, source: 'Songs');
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
        source: 'Album',
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
        source: 'Album',
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
      await player().playList(six, start: 0, source: 'Songs', shuffle: true);
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
}
