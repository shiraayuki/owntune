import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/home/home_providers.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/playlists/liked_songs.dart';

import '../support/fakes.dart';

/// A [FakeHomeRepository] whose streams the test controls.
class _ControlledHome extends FakeHomeRepository {
  final recentController = StreamController<List<RecentSource>>();
  final topController = StreamController<List<TrackPlayCount>>();

  @override
  Stream<List<RecentSource>> watchRecentSources({
    required DateTime since,
    int limit = 20,
  }) {
    recentSince.add(since);
    return recentController.stream;
  }

  @override
  Stream<List<TrackPlayCount>> watchTopTracks({
    required DateTime since,
    int limit = 50,
  }) {
    topSince.add(since);
    return topController.stream;
  }
}

void main() {
  late ProviderContainer container;

  ProviderContainer makeContainer(
    FakeHomeRepository home,
    DateTime Function() clock,
  ) {
    final c = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(home),
        clockProvider.overrideWithValue(clock),
        libraryProvider.overrideWithValue(
          AsyncData(Library.from([track(1, title: 'S1', artist: 'A')])),
        ),
        playlistsProvider.overrideWithValue(const AsyncData([])),
        likedSongsProvider.overrideWithValue(const AsyncData([])),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('stays loading while the history streams have no value', () async {
    final home = _ControlledHome();
    addTearDown(home.recentController.close);
    addTearDown(home.topController.close);
    container = makeContainer(home, () => DateTime(2026, 11, 24, 12));
    container.listen(forYouProvider, (_, _) {});

    await pumpEventQueue();
    expect(container.read(forYouProvider).isLoading, isTrue);

    // One of the two is not enough.
    home.recentController.add(const []);
    await pumpEventQueue();
    expect(container.read(forYouProvider).isLoading, isTrue);

    home.topController.add(const []);
    await pumpEventQueue();
    expect(container.read(forYouProvider).hasValue, isTrue);
  });

  test('a failing history counts as empty, without an error', () async {
    final home = _ControlledHome();
    addTearDown(home.recentController.close);
    addTearDown(home.topController.close);
    container = makeContainer(home, () => DateTime(2026, 11, 24, 12));
    container.listen(forYouProvider, (_, _) {});

    home.recentController.addError('no table plays');
    home.topController.addError('no table plays');
    await pumpEventQueue();

    final value = container.read(forYouProvider);
    expect(value.hasError, isFalse);
    final forYou = value.requireValue;
    expect(forYou.onRepeat, isEmpty);
    expect(forYou.neverPlayed, hasLength(1));
  });

  test('the history windows move with the day', () async {
    final home = FakeHomeRepository();
    var now = DateTime(2026, 11, 24, 15, 30);
    container = makeContainer(home, () => now);
    container.listen(forYouProvider, (_, _) {});
    await pumpEventQueue();

    expect(home.topSince, [DateTime(2026, 10, 25)]);
    expect(home.recentSince, [DateTime(2025, 11, 24)]);

    // The same day: a rebuild keeps the streams.
    now = DateTime(2026, 11, 24, 23, 59);
    container.invalidate(forYouProvider);
    await pumpEventQueue();
    expect(home.topSince, hasLength(1));

    // Past midnight: the next rebuild queries with the new windows.
    now = DateTime(2026, 11, 25, 0, 1);
    container.invalidate(forYouProvider);
    await pumpEventQueue();
    expect(home.topSince.last, DateTime(2026, 10, 26));
    expect(home.recentSince.last, DateTime(2025, 11, 25));
    expect(container.read(forYouProvider).hasValue, isTrue);
  });
}
