import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/home/stats_period.dart';
import 'package:owntune/home/stats_providers.dart';
import 'package:owntune/home/stats_repository.dart';

import '../support/fakes.dart';

const _min = 60000;

// Wed 2026-11-25 20:00.
final _clock = clockProvider.overrideWithValue(
  () => DateTime(2026, 11, 25, 20),
);

/// A repository whose track totals fail.
class _FailingStats extends FakeStatsRepository {
  @override
  Stream<List<TrackTotal>> watchTrackTotals({
    required DateTime from,
    required DateTime to,
  }) => Stream.error(StateError('history disk error'));
}

/// History with [plays] counted plays and an hour of listening, all in the
/// current week and month.
FakeStatsRepository _history({int plays = 6}) => FakeStatsRepository()
  ..buckets = [ListeningBucket(DateTime(2026, 11, 24), 60 * _min, plays)]
  ..totals = [TrackTotal(1, plays, 60 * _min)]
  ..hourly = [for (var h = 0; h < 24; h++) h == 20 ? 60 * _min : 0]
  ..history = {1: (first: DateTime(2026, 11, 24), counted: plays)}
  ..firstPlayAt = DateTime(2026, 10, 1);

Future<void> _openStats(
  WidgetTester t, {
  List<Track> songs = const [],
  FakeStatsRepository? stats,
  Future<int> Function()? storageBytes,
  List<Override> overrides = const [],
}) async {
  await pumpApp(
    t,
    songs: songs,
    stats: stats ?? _history(),
    overrides: [
      _clock,
      storageBytesProvider.overrideWith(
        (ref) => (storageBytes ?? () async => 5 * 1024 * 1024)(),
      ),
      ...overrides,
    ],
  );
  await t.tap(find.text('Stats'));
  await t.pumpAndSettle();
}

int _bars(WidgetTester t) => t
    .widgetList(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('stats-bar-'),
      ),
    )
    .length;

void main() {
  final songs = [
    track(
      1,
      title: 'Song A',
      artist: 'Ann',
      album: 'Alb',
      genre: 'Pop',
      playCount: 6,
    ),
  ];

  testWidgets('chips switch the period and the eyebrow follows', (t) async {
    await _openStats(t, songs: songs);
    expect(find.text('Listening time · this week'), findsOneWidget);
    expect(find.text('1 h 00 min'), findsWidgets);
    expect(_bars(t), 7);

    await t.tap(find.byKey(const Key('stats-chip-month')));
    await t.pumpAndSettle();
    expect(find.text('Listening time · this month'), findsOneWidget);
    expect(find.text('Listening time · this week'), findsNothing);
    expect(_bars(t), 30);

    await t.tap(find.byKey(const Key('stats-chip-year')));
    await t.pumpAndSettle();
    expect(find.text('Listening time · this year'), findsOneWidget);
    expect(_bars(t), 12);

    await t.tap(find.byKey(const Key('stats-chip-allTime')));
    await t.pumpAndSettle();
    expect(find.text('Listening time · all time'), findsOneWidget);
  });

  testWidgets('chips use the day bucket for week and month, the month bucket '
      'for year and all time', (t) async {
    final stats = _history();
    await _openStats(t, songs: songs, stats: stats);
    for (final chip in ['month', 'year', 'allTime']) {
      await t.tap(find.byKey(Key('stats-chip-$chip')));
      await t.pumpAndSettle();
    }
    final byRange = {
      for (final r in stats.bucketRanges) (r.from, r.bucket): r.to,
    };
    // Week and month by day, year and all time by month.
    expect(byRange[(DateTime(2026, 11, 23), StatsBucket.day)], isNotNull);
    expect(byRange[(DateTime(2026, 11), StatsBucket.day)], isNotNull);
    expect(byRange[(DateTime(2026), StatsBucket.month)], isNotNull);
    expect(
      byRange[(DateTime.fromMillisecondsSinceEpoch(0), StatsBucket.month)],
      DateTime(2026, 11, 26),
    );
  });

  testWidgets('threshold at 5 counted plays: 4 show the hint', (t) async {
    await _openStats(t, songs: songs, stats: _history(plays: 4));
    expect(find.byKey(const Key('stats-not-enough')), findsOneWidget);
    expect(find.text('Stats fill up as you listen'), findsOneWidget);
    expect(
      find.text(
        'Play a few songs and your listening time, streak, top artists and '
        'favorite hours show up here.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stats-library')), findsOneWidget);
    expect(find.byKey(const Key('stats-chip-week')), findsNothing);
    expect(find.byKey(const Key('stats-listening')), findsNothing);
  });

  testWidgets('the threshold reads the counted-plays count', (t) async {
    // The buckets add up to 6, but the whole history has 4 counted plays.
    await _openStats(t, songs: songs, stats: _history()..countedPlays = 4);
    expect(find.byKey(const Key('stats-not-enough')), findsOneWidget);
  });

  testWidgets('five counted plays show the full page', (t) async {
    await _openStats(t, songs: songs, stats: _history(plays: 5));
    expect(find.byKey(const Key('stats-not-enough')), findsNothing);
    expect(find.byKey(const Key('stats-chip-week')), findsOneWidget);
    expect(find.byKey(const Key('stats-listening')), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const Key('stats-library')),
      200,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 40,
    );
    expect(find.byKey(const Key('stats-library')), findsOneWidget);
  });

  testWidgets('the full page shows every section', (t) async {
    await _openStats(t, songs: songs);
    // The ListView builds lazily; scroll each section into view.
    final list = find.byType(Scrollable).last;
    const sections = {
      'stats-listening': 'Listening time · this week',
      'stats-streak': 'Listening streak',
      'stats-songs-played': 'Songs played',
      'stats-top-artists': 'Ann',
      'stats-top-songs': 'Song A',
      'stats-top-albums': 'Alb',
      'stats-time-of-day': 'You listen most around 8 PM',
      'stats-genres': 'Genre mix · 6 plays this week',
      'stats-recap': 'Your November so far',
      'stats-library': 'Storage used',
    };
    for (final MapEntry(:key, :value) in sections.entries) {
      await t.scrollUntilVisible(
        find.byKey(Key(key)),
        200,
        scrollable: list,
        maxScrolls: 40,
      );
      expect(
        find.descendant(of: find.byKey(Key(key)), matching: find.text(value)),
        findsWidgets,
        reason: key,
      );
    }
    expect(find.text('Top song · 6 plays'), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const Key('stats-most-played')),
      200,
      scrollable: list,
      maxScrolls: 40,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('stats-most-played')),
        matching: find.text('Song A'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('history error shows Could not load Stats and still the '
      'library overview', (t) async {
    await _openStats(t, songs: songs, stats: _FailingStats());
    expect(find.text('Could not load Stats'), findsOneWidget);
    expect(find.textContaining('history disk error'), findsOneWidget);
    expect(find.byKey(const Key('stats-library')), findsOneWidget);
    expect(find.byKey(const Key('stats-listening')), findsNothing);
    expect(find.byKey(const Key('stats-chip-week')), findsNothing);
  });

  testWidgets('empty sections are hidden', (t) async {
    // Five counted plays in the buckets, but no per-song totals and no
    // listening per hour.
    final stats = _history()
      ..totals = []
      ..hourly = List.filled(24, 0);
    await _openStats(t, songs: songs, stats: stats);
    final list = find.byType(Scrollable).last;
    await t.scrollUntilVisible(
      find.byKey(const Key('stats-library')),
      200,
      scrollable: list,
      maxScrolls: 40,
    );
    for (final key in [
      'stats-top-artists',
      'stats-top-songs',
      'stats-top-albums',
      'stats-time-of-day',
      'stats-genres',
    ]) {
      expect(find.byKey(Key(key), skipOffstage: false), findsNothing);
    }
  });

  testWidgets('empty library shows the Import Music empty state', (t) async {
    final picker = FakePicker();
    await pumpApp(t, picker: picker, overrides: [_clock]);
    await t.tap(find.text('Stats'));
    await t.pumpAndSettle();
    final empty = find.byKey(const Key('stats-empty'));
    expect(empty, findsOneWidget);
    expect(find.byKey(const Key('stats-library')), findsNothing);
    await t.tap(
      find.descendant(of: empty, matching: find.text('Import Music')),
    );
    await t.pumpAndSettle();
    expect(picker.picks, 1);
  });

  testWidgets('your library shows counts and storage', (t) async {
    await _openStats(
      t,
      songs: [
        track(1, title: 'A', artist: 'Ann', album: 'X', durationMs: 20 * _min),
        track(2, title: 'B', artist: 'Ann', album: 'X', durationMs: 20 * _min),
        track(3, title: 'C', artist: 'Bob', album: 'Y', durationMs: 25 * _min),
      ],
      stats: _history(plays: 4),
    );
    final library = find.byKey(const Key('stats-library'));
    String value(String label) {
      expect(
        find.descendant(of: library, matching: find.text(label)),
        findsOneWidget,
      );
      final text = t.widget<Text>(
        find.descendant(
          of: find.byKey(Key('stats-library-n-$label')),
          matching: find.byType(Text),
        ),
      );
      return (text.textSpan ?? TextSpan(text: text.data)).toPlainText();
    }

    expect(value('Songs'), '3');
    expect(value('Albums'), '2');
    expect(value('Artists'), '2');
    expect(value('Playlists'), '0');
    expect(value('Total duration'), '1 h 05 min');
    expect(value('Storage used'), '5 MB');
  });

  testWidgets('storage shows an ellipsis while it is unknown', (t) async {
    await _openStats(
      t,
      songs: songs,
      stats: _history(plays: 4),
      storageBytes: () => Completer<int>().future,
    );
    expect(find.text('…'), findsOneWidget);
  });

  testWidgets('the period is kept for the session', (t) async {
    await _openStats(t, songs: songs);
    await t.tap(find.byKey(const Key('stats-chip-year')));
    await t.pumpAndSettle();
    final container = ProviderScope.containerOf(
      t.element(find.byKey(const Key('stats-chip-year'))),
    );
    expect(container.read(statsPeriodProvider), StatsPeriod.year);
  });
}
