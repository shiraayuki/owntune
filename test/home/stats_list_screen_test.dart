import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/home/stats_providers.dart';
import 'package:owntune/home/stats_repository.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/queue_source.dart';

import '../support/fakes.dart';

const _min = 60000;

// Wed 2026-11-25 20:00.
final _clock = clockProvider.overrideWithValue(
  () => DateTime(2026, 11, 25, 20),
);

Future<void> _tall(WidgetTester t) async {
  t.view.physicalSize = const Size(2000, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

PlayerState _state(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(OwntuneApp)))
        .read(playerProvider);

Finder _navBack(String label) =>
    find.descendant(of: find.byType(NavRow), matching: find.text(label));

/// [count] songs by their own artists and albums; song `i` was played
/// `100 - i` times.
List<Track> _songs(int count) => [
  for (var i = 1; i <= count; i++)
    track(
      i,
      title: 'Song $i',
      artist: 'Artist $i',
      album: 'Album $i',
      playCount: 100 - i,
    ),
];

FakeStatsRepository _history(int count) => FakeStatsRepository()
  ..buckets = [ListeningBucket(DateTime(2026, 11, 24), 60 * _min, 100)]
  ..totals = [
    for (var i = 1; i <= count; i++) TrackTotal(i, 100 - i, 10 * _min),
  ]
  ..hourly = [for (var h = 0; h < 24; h++) h == 20 ? 60 * _min : 0]
  ..history = {
    for (var i = 1; i <= count; i++)
      i: (first: DateTime(2026, 11, 24), counted: 100 - i),
  }
  ..firstPlayAt = DateTime(2026, 10, 1);

/// Track totals that never arrive once [stall] is set, as when the streams
/// move to the new day.
class _StallingStats extends FakeStatsRepository {
  bool stall = false;

  @override
  Stream<List<TrackTotal>> watchTrackTotals({
    required DateTime from,
    required DateTime to,
  }) => stall
      ? StreamController<List<TrackTotal>>().stream
      : super.watchTrackTotals(from: from, to: to);
}

Future<void> _openStats(
  WidgetTester t, {
  required int count,
  FakeAudioEngine? engine,
}) async {
  await _tall(t);
  await pumpApp(
    t,
    songs: _songs(count),
    stats: _history(count),
    engine: engine,
    overrides: [_clock, storageBytesProvider.overrideWith((ref) async => 1024)],
  );
  await t.tap(find.text('Stats'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('See All opens the full Top Songs list with up to 50 rows', (
    t,
  ) async {
    await _openStats(t, count: 60);
    await t.tap(find.byKey(const Key('stats-see-all-songs')));
    await t.pumpAndSettle();

    expect(_navBack('Home'), findsOneWidget);
    expect(find.text('Top Songs'), findsOneWidget);
    expect(find.byKey(const Key('stats-list-0')), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const Key('stats-list-49')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Song 50'), findsOneWidget);
    expect(find.byKey(const Key('stats-list-50')), findsNothing);
    expect(find.text('Song 51'), findsNothing);
  });

  testWidgets('See All opens Top Artists and Top Albums', (t) async {
    await _openStats(t, count: 6);
    await t.tap(find.byKey(const Key('stats-see-all-artists')));
    await t.pumpAndSettle();
    expect(find.text('Top Artists'), findsOneWidget);
    expect(find.text('Artist 6'), findsOneWidget);
    await t.tap(_navBack('Home'));
    await t.pumpAndSettle();

    await t.scrollUntilVisible(
      find.byKey(const Key('stats-see-all-albums')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.byKey(const Key('stats-see-all-albums')));
    await t.pumpAndSettle();
    expect(find.text('Top Albums'), findsOneWidget);
    expect(find.text('Album 6'), findsOneWidget);
  });

  testWidgets('a song row plays the list from it with the Top Songs source', (
    t,
  ) async {
    final engine = FakeAudioEngine();
    await _openStats(t, count: 15, engine: engine);
    // On the Stats page: the second row of the top three.
    await t.scrollUntilVisible(
      find.byKey(const Key('stats-songs-1')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.byKey(const Key('stats-songs-1')));
    await t.pumpAndSettle();
    expect(
      _state(t).queue.source,
      const QueueSource(QueueSourceKind.other, 'Top Songs'),
    );
    expect(_state(t).queue.index, 1);
    expect(_state(t).queue.entries.length, 15);
    expect(engine.loaded, ['hash2.mp3']);
  });

  testWidgets('a row in the full Top Songs list plays the list from it', (
    t,
  ) async {
    final engine = FakeAudioEngine();
    await _openStats(t, count: 15, engine: engine);
    await t.tap(find.byKey(const Key('stats-see-all-songs')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stats-list-3')));
    await t.pumpAndSettle();

    expect(engine.loaded, ['hash4.mp3']);
    expect(_state(t).queue.index, 3);
    expect(
      [for (final e in _state(t).queue.entries) e.trackId],
      [for (var i = 1; i <= 15; i++) i],
    );
    expect(
      _state(t).queue.source,
      const QueueSource(QueueSourceKind.other, 'Top Songs'),
    );
  });

  testWidgets('an artist row opens the artist page', (t) async {
    await _openStats(t, count: 6);
    await t.tap(find.byKey(const Key('stats-artists-1')));
    await t.pumpAndSettle();
    expect(_navBack('Home'), findsOneWidget);
    expect(find.text('Artist 2'), findsWidgets);
    expect(find.text('Song 2'), findsOneWidget);
  });

  testWidgets('an album row in the list opens the album page', (t) async {
    await _openStats(t, count: 6);
    await t.scrollUntilVisible(
      find.byKey(const Key('stats-see-all-albums')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.byKey(const Key('stats-see-all-albums')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stats-list-2')));
    await t.pumpAndSettle();
    // The back label names the list it came from.
    expect(_navBack('Top Albums'), findsOneWidget);
    expect(find.text('Album 3'), findsWidgets);
    expect(find.text('Song 3'), findsOneWidget);
  });

  testWidgets('an artist row in the list opens the artist page back to Top '
      'Artists', (t) async {
    await _openStats(t, count: 6);
    await t.tap(find.byKey(const Key('stats-see-all-artists')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stats-list-1')));
    await t.pumpAndSettle();
    expect(_navBack('Top Artists'), findsOneWidget);
    expect(find.text('Artist 2'), findsWidgets);
    expect(find.text('Song 2'), findsOneWidget);
  });

  testWidgets('a Most Played row plays the five with the Most Played source', (
    t,
  ) async {
    final engine = FakeAudioEngine();
    await _openStats(t, count: 12, engine: engine);
    await t.scrollUntilVisible(
      find.byKey(const Key('stats-most-played-2')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.byKey(const Key('stats-most-played-2')));
    await t.pumpAndSettle();

    expect(engine.loaded, ['hash3.mp3']);
    expect(_state(t).queue.index, 2);
    expect(
      [for (final e in _state(t).queue.entries) e.trackId],
      [1, 2, 3, 4, 5],
    );
    expect(
      _state(t).queue.source,
      const QueueSource(QueueSourceKind.other, 'Most Played'),
    );
  });

  testWidgets('the full list keeps its rows while Stats reloads', (t) async {
    await _tall(t);
    var now = DateTime(2026, 11, 25, 20);
    final stats = _StallingStats()
      ..buckets = _history(6).buckets
      ..totals = _history(6).totals
      ..hourly = _history(6).hourly
      ..history = _history(6).history
      ..firstPlayAt = DateTime(2026, 10, 1);
    await pumpApp(
      t,
      songs: _songs(6),
      stats: stats,
      overrides: [
        clockProvider.overrideWithValue(() => now),
        storageBytesProvider.overrideWith((ref) async => 1024),
      ],
    );
    await t.tap(find.text('Stats'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stats-see-all-songs')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('stats-list-5')), findsOneWidget);

    // Past midnight the streams move to the new day and load again.
    stats.stall = true;
    now = DateTime(2026, 11, 26, 0, 1);
    final container = ProviderScope.containerOf(
      t.element(find.byType(OwntuneApp)),
    );
    container.invalidate(statsProvider);
    await t.pump();
    expect(container.read(statsProvider).isLoading, isTrue);
    expect(find.byKey(const Key('stats-list-0')), findsOneWidget);
    expect(find.byKey(const Key('stats-list-5')), findsOneWidget);
  });
}
