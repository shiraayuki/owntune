import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/home/stats_providers.dart';
import 'package:owntune/home/stats_repository.dart';
import 'package:owntune/library/library.dart';

import '../support/fakes.dart';

const _min = 60000;

/// Counts the storage scans.
class _CountingTracks extends FakeTrackRepository {
  int scans = 0;

  @override
  Future<int> storageBytes() async {
    scans++;
    return 1024;
  }
}

void main() {
  group('previous range', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> play(DateTime at, {int listenedMs = 10 * _min}) => db
        .into(db.plays)
        .insert(
          PlaysCompanion.insert(
            trackId: 1,
            startedAt: at,
            listenedMs: listenedMs,
            counted: true,
          ),
        );

    Future<StatsView> settle(ProviderContainer c) async {
      for (var i = 0; i < 100; i++) {
        final value = c.read(statsProvider);
        if (value.hasValue) return value.requireValue;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('statsProvider stayed loading');
    }

    test('is cut at the exact time a week earlier, not at the end of that '
        'day', () async {
      // Early history, so the delta is shown; outside both weeks.
      for (var i = 0; i < 3; i++) {
        await play(DateTime(2026, 11, 2, 10 + i));
      }
      // Last Wednesday: 08:00 is before the cut (12:00), 18:00 after it.
      await play(DateTime(2026, 11, 18, 8));
      await play(DateTime(2026, 11, 18, 18));
      // This Wednesday: the same 08:00 listening.
      await play(DateTime(2026, 11, 25, 8));

      final c = ProviderContainer(
        overrides: [
          statsRepositoryProvider.overrideWithValue(StatsRepository(db)),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 25, 12)),
          libraryProvider.overrideWithValue(
            AsyncData(Library.from([track(1, title: 'S1', artist: 'A')])),
          ),
          playlistsProvider.overrideWithValue(const AsyncData([])),
          storageBytesProvider.overrideWith((ref) async => 0),
        ],
      );
      addTearDown(c.dispose);
      c.listen(statsProvider, (_, _) {});

      final view = await settle(c);
      expect(view.listening!.delta, 'Same as last week');
      expect(view.songsPlayed!.delta, 'Same as last week');
    });
  });

  test('a play-count-only change does not scan the storage again', () async {
    final repo = _CountingTracks();
    final songs = StreamController<List<Track>>();
    addTearDown(songs.close);
    final c = ProviderContainer(
      overrides: [
        trackRepositoryProvider.overrideWithValue(repo),
        tracksProvider.overrideWith((ref) => songs.stream),
      ],
    );
    addTearDown(c.dispose);
    c.listen(storageBytesProvider, (_, _) {});

    songs.add([track(1, playCount: 1)]);
    await pumpEventQueue();
    final scans = repo.scans;
    expect(c.read(storageBytesProvider).value, 1024);

    songs.add([track(1, playCount: 2)]);
    await pumpEventQueue();
    expect(repo.scans, scans);

    // A new file does.
    songs.add([track(1, playCount: 2), track(2)]);
    await pumpEventQueue();
    expect(repo.scans, scans + 1);
  });
}
