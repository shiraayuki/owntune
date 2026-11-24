import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/home/home_providers.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/home/stats_providers.dart';
import 'package:owntune/home/stats_repository.dart';
import 'package:owntune/library/navigation.dart';

import '../support/fakes.dart';

final _evening = clockProvider.overrideWithValue(
  () => DateTime(2026, 11, 24, 20),
);

/// Counts the recomputations of [statsProvider] and [forYouProvider].
final class _Updates extends ProviderObserver {
  int stats = 0;
  int forYou = 0;

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (context.provider == statsProvider) stats++;
    if (context.provider == forYouProvider) forYou++;
  }
}

/// Live streams, like drift's: every listen gets its own controller that
/// starts with the current value; [emit] sends a new value to all of them.
class _Live<T> {
  _Live(this.value);

  T value;
  final controllers = <StreamController<T>>[];

  Stream<T> stream() {
    late final StreamController<T> c;
    c = StreamController<T>(onListen: () => c.add(value));
    controllers.add(c);
    return c.stream;
  }

  Iterable<StreamController<T>> get listened =>
      controllers.where((c) => c.hasListener);

  void emit(T next) {
    value = next;
    for (final c in listened) {
      c.add(next);
    }
  }

  void close() {
    for (final c in controllers) {
      c.close();
    }
  }
}

class _LiveStats extends FakeStatsRepository {
  final live = _Live<List<ListeningBucket>>([
    ListeningBucket(DateTime(2026, 11, 24), 60 * 60000, 6),
  ]);

  @override
  Stream<List<ListeningBucket>> watchListeningBuckets({
    required DateTime from,
    required DateTime to,
    required StatsBucket bucket,
    bool countedOnly = false,
  }) => live.stream();
}

class _LiveHome extends FakeHomeRepository {
  final live = _Live<List<TrackPlayCount>>(const []);

  @override
  Stream<List<TrackPlayCount>> watchTopTracks({
    required DateTime since,
    int limit = 50,
  }) => live.stream();
}

void main() {
  testWidgets('the app opens on Home with the greeting', (t) async {
    await pumpApp(t, songs: [track(1)], overrides: [_evening]);
    expect(find.text('Good evening'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.house_fill), findsOneWidget);
    expect(find.byKey(const Key('home-segments')), findsOneWidget);
  });

  testWidgets('the greeting follows the clock', (t) async {
    await pumpApp(
      t,
      songs: [track(1)],
      overrides: [
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 24, 8)),
      ],
    );
    expect(find.text('Good morning'), findsOneWidget);
  });

  testWidgets('sub-tabs switch to Stats and back', (t) async {
    await pumpApp(t, songs: [track(1)], overrides: [_evening]);
    // Both sub-tabs stay mounted; only the visible one is on stage.
    expect(find.byKey(const Key('stats-not-enough')), findsNothing);
    await t.tap(find.text('Stats'));
    await t.pumpAndSettle();
    // A fresh history has too few plays for the full page.
    expect(find.byKey(const Key('stats-not-enough')), findsOneWidget);
    expect(find.text('Stats fill up as you listen'), findsOneWidget);
    expect(find.byKey(const Key('stats-library')), findsOneWidget);
    await t.tap(find.text('For You'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('stats-not-enough')), findsNothing);
  });

  testWidgets('empty library shows Import Music and Search Online', (t) async {
    final picker = FakePicker();
    await pumpApp(t, picker: picker, overrides: [_evening]);
    expect(find.byKey(const Key('for-you-empty')), findsOneWidget);
    expect(find.text('Your music lives here'), findsOneWidget);
    expect(
      find.text('Import files you already have, or find songs on YouTube.'),
      findsOneWidget,
    );
    // The sub-tabs stay visible, unlike on Library.
    expect(find.byKey(const Key('home-segments')), findsOneWidget);

    await t.tap(
      find.descendant(
        of: find.byKey(const Key('for-you-empty')),
        matching: find.text('Import Music'),
      ),
    );
    await t.pumpAndSettle();
    expect(picker.picks, 1);
  });

  testWidgets('Search Online from the empty state has the back label Home', (
    t,
  ) async {
    await pumpApp(t, overrides: [_evening]);
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('for-you-empty')),
        matching: find.text('Search Online'),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(NavRow), matching: find.text('Home')),
      findsOneWidget,
    );
  });

  testWidgets('"+" → Search Online on Home has the back label Home, not the '
      'greeting', (t) async {
    await pumpApp(t, songs: [track(1)], overrides: [_evening]);
    await t.tap(find.byKey(const Key('import-button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-search-online')));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(NavRow), matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NavRow),
        matching: find.text('Good evening'),
      ),
      findsNothing,
    );
  });

  testWidgets('a failing library load shows Could not load Home', (t) async {
    await pumpApp(
      t,
      songsStream: Stream.error(StateError('disk I/O error')),
      overrides: [_evening],
    );
    expect(find.text('Could not load Home'), findsOneWidget);
    expect(find.textContaining('disk I/O error'), findsOneWidget);
  });

  testWidgets('hidden Home sub-tabs pause their streams and do not recompute; '
      'returning shows current data', (t) async {
    final stats = _LiveStats()
      ..totals = [const TrackTotal(1, 6, 60 * 60000)]
      ..countedPlays = 6
      ..firstPlayAt = DateTime(2026, 10, 1);
    final home = _LiveHome();
    addTearDown(stats.live.close);
    addTearDown(home.live.close);
    final songs = StreamController<List<Track>>();
    addTearDown(songs.close);
    final updates = _Updates();
    songs.add([track(1, title: 'Song A', artist: 'Ann', playCount: 6)]);
    await pumpApp(
      t,
      songsStream: songs.stream,
      stats: stats,
      home: home,
      observers: [updates],
      overrides: [_evening],
    );
    await t.tap(find.text('Stats'));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('stats-listening')),
        matching: find.text('1 h 00 min'),
      ),
      findsWidgets,
    );
    // For You is the hidden sub-tab now.
    expect(home.live.listened, isNotEmpty);
    expect(home.live.listened.every((c) => c.isPaused), isTrue);

    await openLibraryTab(t);
    await t.pumpAndSettle();
    expect(stats.live.listened, isNotEmpty);
    expect(stats.live.listened.every((c) => c.isPaused), isTrue);
    final statsBefore = updates.stats;
    final forYouBefore = updates.forYou;

    // Playback moves the history and the play count while Library is shown.
    stats.live.emit([ListeningBucket(DateTime(2026, 11, 24), 120 * 60000, 7)]);
    home.live.emit([const TrackPlayCount(1, 7)]);
    songs.add([track(1, title: 'Song A', artist: 'Ann', playCount: 7)]);
    await t.pumpAndSettle();
    expect(updates.stats, statsBefore);
    expect(updates.forYou, forYouBefore);

    await t.tap(
      find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.text('Home'),
      ),
    );
    await t.pumpAndSettle();
    expect(updates.stats, greaterThan(statsBefore));
    expect(
      find.descendant(
        of: find.byKey(const Key('stats-listening')),
        matching: find.text('2 h 00 min'),
      ),
      findsWidgets,
    );
  });
}
