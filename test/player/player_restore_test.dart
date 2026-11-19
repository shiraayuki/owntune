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

import '../support/fakes.dart';

final a = track(1, title: 'A');
final b = track(2, title: 'B');
final c = track(3, title: 'C');

void main() {
  late FakeAudioEngine engine;
  late FakePlayerStateStore store;
  late StreamController<List<Track>> library;
  late ProviderContainer container;

  ProviderContainer make(PlayerSnapshot? saved) {
    final c = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        storageProvider.overrideWithValue(
          LibraryStorage(Directory('/nonexistent/owntune')),
        ),
        tracksProvider.overrideWith((ref) => library.stream),
        playerStateStoreProvider.overrideWithValue(store),
        initialPlayerSnapshotProvider.overrideWithValue(saved),
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
  });

  tearDown(() async {
    container.dispose();
    await library.close();
  });

  const saved = PlayerSnapshot(
    trackIds: [1, 2, 3],
    index: 1,
    source: 'Paper Lanterns',
    repeat: QueueRepeat.all,
    position: Duration(seconds: 84),
  );

  test('restores paused at the saved position', () async {
    container = make(saved);
    library.add([a, b, c]);
    await pumpEventQueue();

    expect(ids(), [1, 2, 3]);
    expect(state().queue.index, 1);
    expect(state().queue.source, 'Paper Lanterns');
    expect(state().queue.repeat, QueueRepeat.all);
    expect(state().playing, isFalse);
    expect(engine.current, 'hash2.mp3');
    expect(engine.playing, isFalse);
    expect(engine.lastSeek, const Duration(seconds: 84));
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

    await player().playList([a, b, c], start: 0, source: 'Songs');
    await pumpEventQueue();
    expect(store.saved!.trackIds, [1, 2, 3]);
    expect(store.saved!.source, 'Songs');
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
    await player().playList([a, b, c], start: 0, source: 'Songs');
    await player().seek(const Duration(seconds: 42));
    await pumpEventQueue();
    expect(store.saved!.position, const Duration(seconds: 42));
  });

  test('repeat and queue edits are saved', () async {
    container = make(null);
    library.add([a, b, c]);
    await pumpEventQueue();
    await player().playList([a, b, c], start: 0, source: 'Songs');
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
    await player().playList([a], start: 0, source: 'Songs');
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
    await player().playList([a, b, c], start: 1, source: 'Songs');
    player().toggleShuffle();
    await pumpEventQueue();
    final s = store.saved!;
    expect(s.trackIds.first, 2);
    expect([for (final p in s.shuffleOrder!) s.trackIds[p]], [1, 2, 3]);
  });
}
