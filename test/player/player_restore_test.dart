import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/player/play_queue.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/player_snapshot.dart';
import 'package:owntune/player/queue_source.dart';

import '../support/fakes.dart';

final a = track(1, title: 'A');
final b = track(2, title: 'B');
final c = track(3, title: 'C');

void main() {
  late FakeAudioEngine engine;
  late FakePlayerStateStore store;
  late StreamController<List<Track>> library;
  late ProviderContainer container;
  late FakePlayRepository plays;
  late DateTime now;

  ProviderContainer make(PlayerSnapshot? saved) {
    final c = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        playRepositoryProvider.overrideWithValue(plays),
        clockProvider.overrideWithValue(() => now),
        storageProvider.overrideWithValue(
          LibraryStorage(Directory('/nonexistent/owntune')),
        ),
        tracksProvider.overrideWith((ref) => library.stream),
        playerStateStoreProvider.overrideWithValue(store),
        initialPlayerSnapshotProvider.overrideWithValue(saved),
        loudnessRepositoryProvider.overrideWithValue(
          FakeLoudnessRepository(lufs: {2: -8}),
        ),
      ],
    );
    c.listen(playerProvider, (_, _) {});
    c.listen(currentTrackProvider, (_, _) {});
    return c;
  }

  PlayerState state() => container.read(playerProvider);
  PlayerController player() => container.read(playerProvider.notifier);
  List<int> ids() => [for (final e in state().queue.entries) e.trackId];

  setUp(() {
    engine = FakeAudioEngine();
    store = FakePlayerStateStore();
    library = StreamController<List<Track>>();
    plays = FakePlayRepository();
    now = DateTime(2026, 11, 24, 8);
  });

  tearDown(() async {
    container.dispose();
    await library.close();
  });

  final saved = PlayerSnapshot(
    trackIds: [1, 2, 3],
    index: 1,
    source: QueueSource(QueueSourceKind.album, 'Paper Lanterns'),
    repeat: QueueRepeat.all,
    position: Duration(seconds: 84),
  );

  test('restores paused at the saved position', () async {
    container = make(saved);
    library.add([a, b, c]);
    await pumpEventQueue();

    expect(ids(), [1, 2, 3]);
    expect(state().queue.index, 1);
    expect(state().queue.source, saved.source);
    expect(state().queue.repeat, QueueRepeat.all);
    expect(state().playing, isFalse);
    expect(engine.current, 'hash2.mp3');
    expect(engine.playing, isFalse);
    expect(engine.lastSeek, const Duration(seconds: 84));
  });

  test('a restored queue sets the volume before the first play', () async {
    container = make(saved);
    library.add([a, b, c]);
    await pumpEventQueue();

    expect(engine.volumes.last, closeTo(0.5012, 1e-3));
    expect(engine.calls, isNot(contains('play')));
  });

  test('queued entries are saved and restored', () async {
    container = make(null);
    library.add([a, b, c]);
    await pumpEventQueue();
    await player().playList(
      [a, b],
      start: 0,
      source: const QueueSource.songs(),
    );
    await player().playNext(c);
    await pumpEventQueue();
    expect(store.saved!.queuedPositions, [1]);
    final snapshot = store.saved!;
    container.dispose();
    await library.close();
    library = StreamController<List<Track>>();

    container = make(snapshot);
    library.add([a, b, c]);
    await pumpEventQueue();
    expect(ids(), [1, 3, 2]);
    expect(
      [for (final e in state().queue.entries) e.queued],
      [false, true, false],
    );
  });

  test('drops songs deleted since and starts the next one at zero', () async {
    container = make(saved);
    library.add([a, c]);
    await pumpEventQueue();

    expect(ids(), [1, 3]);
    expect(state().queue.current!.trackId, 3);
    expect(engine.current, 'hash3.mp3');
    expect(engine.lastSeek ?? Duration.zero, Duration.zero);
    expect(engine.playing, isFalse);
  });

  test('restores nothing when no song is left', () async {
    container = make(saved);
    library.add([track(9, title: 'Other')]);
    await pumpEventQueue();

    expect(state().queue.isEmpty, isTrue);
    expect(engine.loaded, isEmpty);
    expect(store.saved, isNull);
  });

  test('saves after playList, after pause and every five seconds', () async {
    container = make(null);
    library.add([a, b, c]);
    await pumpEventQueue();

    await player().playList(
      [a, b, c],
      start: 0,
      source: const QueueSource.songs(),
    );
    await pumpEventQueue();
    expect(store.saved!.trackIds, [1, 2, 3]);
    expect(store.saved!.source, const QueueSource.songs());
    final afterPlay = store.saves;

    for (var s = 1; s <= 12; s++) {
      engine.emitPosition(Duration(seconds: s));
    }
    await pumpEventQueue();
    expect(store.saves, afterPlay + 2);
    expect(store.saved!.position, const Duration(seconds: 10));

    engine.emitPosition(const Duration(seconds: 13));
    await pumpEventQueue();
    await player().togglePlay();
    await pumpEventQueue();
    expect(store.saved!.position, const Duration(seconds: 13));
  });

  test('a seek saves the new position', () async {
    container = make(null);
    library.add([a, b, c]);
    await pumpEventQueue();
    await player().playList(
      [a, b, c],
      start: 0,
      source: const QueueSource.songs(),
    );
    await player().seek(const Duration(seconds: 42));
    await pumpEventQueue();
    expect(store.saved!.position, const Duration(seconds: 42));
  });

  test('repeat and queue edits are saved', () async {
    container = make(null);
    library.add([a, b, c]);
    await pumpEventQueue();
    await player().playList(
      [a, b, c],
      start: 0,
      source: const QueueSource.songs(),
    );
    player().cycleRepeat();
    await pumpEventQueue();
    expect(store.saved!.repeat, QueueRepeat.all);
    player().clearUpcoming();
    await pumpEventQueue();
    expect(store.saved!.trackIds, [1]);
  });

  test('an empty queue saves nothing', () async {
    container = make(null);
    library.add([a]);
    await pumpEventQueue();
    await player().playList([a], start: 0, source: const QueueSource.songs());
    await pumpEventQueue();
    expect(store.saved, isNotNull);

    library.add([]);
    await pumpEventQueue();
    expect(store.saved, isNull);
  });

  test('restores shuffle and its original order', () async {
    container = make(
      const PlayerSnapshot(
        trackIds: [2, 3, 1],
        index: 0,
        shuffleOrder: [2, 0, 1],
      ),
    );
    library.add([a, b, c]);
    await pumpEventQueue();
    expect(state().queue.shuffled, isTrue);
    expect(ids(), [2, 3, 1]);
    player().toggleShuffle();
    expect(ids(), [1, 2, 3]);
    expect(state().queue.current!.trackId, 2);
  });

  test('saves the shuffle order', () async {
    container = make(null);
    library.add([a, b, c]);
    await pumpEventQueue();
    await player().playList(
      [a, b, c],
      start: 1,
      source: const QueueSource.songs(),
    );
    player().toggleShuffle();
    await pumpEventQueue();
    final s = store.saved!;
    expect(s.trackIds.first, 2);
    expect([for (final p in s.shuffleOrder!) s.trackIds[p]], [1, 2, 3]);
  });
  test('a restored song is recorded from when it plays again', () async {
    container = make(saved);
    library.add([a, b, c]);
    await pumpEventQueue();
    expect(engine.lastSeek, const Duration(seconds: 84));
    now = DateTime(2026, 11, 24, 21);
    await player().togglePlay();
    for (var s = 85; s <= 90; s++) {
      engine.emitPosition(Duration(seconds: s));
      await pumpEventQueue();
    }
    await player().togglePlay();
    await pumpEventQueue();
    final row = plays.rows.values.single;
    expect(row.trackId, 2);
    expect(row.listenedMs, 6000);
    expect(row.startedAt, DateTime(2026, 11, 24, 21));
    expect(row.sourceKind, 'album');
  });

  test('a restored queue without a source is recorded as other', () async {
    container = make(
      PlayerSnapshot(
        trackIds: [1],
        index: 0,
        source: null,
        repeat: QueueRepeat.off,
        position: Duration.zero,
      ),
    );
    library.add([a, b, c]);
    await pumpEventQueue();
    await player().togglePlay();
    for (var s = 1; s <= 3; s++) {
      engine.emitPosition(Duration(seconds: s));
      await pumpEventQueue();
    }
    await player().togglePlay();
    await pumpEventQueue();
    final row = plays.rows.values.single;
    expect(row.sourceKind, 'other');
    expect(row.sourceKey, isNull);
  });
}
