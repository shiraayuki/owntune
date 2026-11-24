import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/home/stats_listening.dart';
import 'package:owntune/home/stats_period.dart';
import 'package:owntune/home/stats_repository.dart';

const _min = 60000;

ListeningBucket _day(int y, int m, int d, int ms, [int plays = 1]) =>
    ListeningBucket(DateTime(y, m, d), ms, plays);

ListeningBucket _month(int y, int m, int ms, [int plays = 1]) =>
    ListeningBucket(DateTime(y, m), ms, plays);

void main() {
  // 2026-11-25 is a Wednesday.
  final wednesday = DateTime(2026, 11, 25, 20);

  ListeningCard card(
    StatsPeriod period,
    DateTime now,
    List<ListeningBucket> buckets, {
    List<ListeningBucket>? previous,
    DateTime? firstPlayAt,
  }) => buildListeningCard(
    period: period,
    now: now,
    buckets: buckets,
    previousBuckets: previous,
    firstPlayAt: firstPlayAt,
  );

  test('week chart has 7 bars with future slots', () {
    expect(wednesday.weekday, DateTime.wednesday);
    final c = card(StatsPeriod.week, wednesday, [
      _day(2026, 11, 23, 10 * _min),
      _day(2026, 11, 25, 30 * _min),
    ]);
    expect(c.eyebrow, 'Listening time · this week');
    expect(c.bars.map((b) => b.label), ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
    expect(c.bars.map((b) => b.future), [
      false,
      false,
      false,
      true,
      true,
      true,
      true,
    ]);
    expect(c.bars[0].listenedMs, 10 * _min);
    expect(c.bars[1].listenedMs, 0);
    expect(c.bars[2].listenedMs, 30 * _min);
    expect(c.maxMs, 30 * _min);
    expect(c.total, '40 min');
  });

  test('month chart has one bar per day with labels 1 8 15 22 29', () {
    final c = card(StatsPeriod.month, wednesday, [_day(2026, 11, 3, _min)]);
    expect(c.eyebrow, 'Listening time · this month');
    expect(c.bars, hasLength(30));
    final labelled = {
      for (var i = 0; i < c.bars.length; i++)
        if (c.bars[i].label != null) i + 1: c.bars[i].label,
    };
    expect(labelled, {1: '1', 8: '8', 15: '15', 22: '22', 29: '29'});
    expect(c.bars[24].future, isFalse);
    expect(c.bars[25].future, isTrue);
    expect(c.bars[2].listenedMs, _min);
  });

  test('year chart has 12 month bars', () {
    final c = card(StatsPeriod.year, wednesday, [
      _month(2026, 1, 60 * _min),
      _month(2026, 11, 120 * _min),
    ]);
    expect(c.eyebrow, 'Listening time · this year');
    expect(c.bars.map((b) => b.label).join(), 'JFMAMJJASOND');
    expect(c.bars, hasLength(12));
    expect(c.bars[10].future, isFalse);
    expect(c.bars[11].future, isTrue);
    expect(c.bars[0].listenedMs, 60 * _min);
    expect(c.bars[10].listenedMs, 120 * _min);
    expect(c.avgLabel, 'avg 1 h 30 min');
  });

  test('all time shows one bar per month up to 24 months', () {
    final first = DateTime(2025, 1, 10);
    final c = card(StatsPeriod.allTime, wednesday, [
      _month(2025, 1, _min),
      _month(2026, 11, 2 * _min),
    ], firstPlayAt: first);
    expect(c.eyebrow, 'Listening time · all time');
    expect(c.bars, hasLength(23));
    expect(c.bars.first.label, 'Jan 2025');
    expect(c.bars.last.label, 'Nov 2026');
    expect(c.bars.where((b) => b.future), isEmpty);
    expect(c.bars.first.listenedMs, _min);
    expect(c.bars.last.listenedMs, 2 * _min);
  });

  test('all time switches to years after 24 months', () {
    final first = DateTime(2023, 6, 1);
    final c = card(StatsPeriod.allTime, wednesday, [
      _month(2023, 6, _min),
      _month(2023, 7, _min),
      _month(2026, 11, 3 * _min),
    ], firstPlayAt: first);
    expect(c.bars, hasLength(4));
    expect(c.bars.first.label, '2023');
    expect(c.bars.last.label, '2026');
    expect(c.bars.map((b) => b.listenedMs), [2 * _min, 0, 0, 3 * _min]);
    expect(c.delta, isNull);
  });

  test('average over elapsed bars with data', () {
    final c = card(StatsPeriod.week, wednesday, [
      _day(2026, 11, 23, 10 * _min),
      _day(2026, 11, 25, 50 * _min),
    ]);
    // Tuesday has no data and the future days are not elapsed.
    expect(c.avgMs, 30 * _min);
    expect(c.avgLabel, 'avg 30 min');
    final empty = card(StatsPeriod.week, wednesday, const []);
    expect(empty.avgMs, 0);
    expect(empty.maxMs, 0);
    expect(empty.total, '0 min');
  });

  test('delta hidden when the previous range predates the history', () {
    final c = card(
      StatsPeriod.week,
      wednesday,
      [_day(2026, 11, 25, 30 * _min)],
      previous: [_day(2026, 11, 18, 5 * _min)],
      // Previous range starts Monday 2026-11-16.
      firstPlayAt: DateTime(2026, 11, 17, 8),
    );
    expect(c.delta, isNull);
    final none = card(
      StatsPeriod.week,
      wednesday,
      [_day(2026, 11, 25, 30 * _min)],
      previous: const [],
      firstPlayAt: null,
    );
    expect(none.delta, isNull);
  });

  test('delta shown when covered', () {
    final first = DateTime(2026, 10, 1);
    final more = card(
      StatsPeriod.week,
      wednesday,
      [_day(2026, 11, 25, 60 * _min)],
      previous: [_day(2026, 11, 18, 12 * _min)],
      firstPlayAt: first,
    );
    expect(more.delta, '+48 min vs. last week');
    final less = card(
      StatsPeriod.month,
      wednesday,
      [_day(2026, 11, 3, 10 * _min)],
      previous: [_day(2026, 10, 3, 75 * _min)],
      firstPlayAt: first,
    );
    expect(less.delta, '−1 h 05 min vs. last month');
    final same = card(
      StatsPeriod.week,
      wednesday,
      const [],
      previous: const [],
      firstPlayAt: DateTime(2026, 11, 16),
    );
    expect(same.delta, 'Same as last week');
  });

  test('streak counts back from today or yesterday', () {
    final now = DateTime(2026, 11, 25, 20);
    final emptyToday = buildStreak(
      allDays: [_day(2026, 11, 24, 1), _day(2026, 11, 23, 1)],
      now: now,
    );
    expect(emptyToday.days, 2);
    expect(emptyToday.label, '2 days');
    final today = buildStreak(
      allDays: [
        _day(2026, 11, 25, 1),
        _day(2026, 11, 24, 1),
        _day(2026, 11, 23, 1),
      ],
      now: now,
    );
    expect(today.days, 3);
    final gap = buildStreak(
      allDays: [
        _day(2026, 11, 25, 1),
        _day(2026, 11, 24, 1),
        _day(2026, 11, 22, 1),
      ],
      now: now,
    );
    expect(gap.days, 2);
    final none = buildStreak(allDays: [_day(2026, 11, 20, 1)], now: now);
    expect(none.days, 0);
    expect(none.label, '0 days');
    final one = buildStreak(allDays: [_day(2026, 11, 25, 1)], now: now);
    expect(one.label, '1 day');
  });

  test('streak ignores days without counted plays', () {
    final s = buildStreak(
      allDays: [_day(2026, 11, 25, 5000, 0), _day(2026, 11, 24, 1000)],
      now: DateTime(2026, 11, 25, 20),
    );
    expect(s.days, 1);
  });

  test('last7 marks played days', () {
    final s = buildStreak(
      allDays: [
        _day(2026, 11, 25, 1),
        _day(2026, 11, 23, 1),
        _day(2026, 11, 19, 1),
        _day(2026, 11, 10, 1),
      ],
      now: DateTime(2026, 11, 25, 20),
    );
    // Nov 19 .. Nov 25, oldest first.
    expect(s.last7, [true, false, false, false, true, false, true]);
  });

  test('songs played delta follows the same hiding rule', () {
    final now = wednesday;
    final shown = buildSongsPlayed(
      period: StatsPeriod.week,
      now: now,
      current: 20,
      previous: 8,
      firstPlayAt: DateTime(2026, 10, 1),
    );
    expect(shown.count, 20);
    expect(shown.delta, '+12 vs. last week');
    final hidden = buildSongsPlayed(
      period: StatsPeriod.week,
      now: now,
      current: 20,
      previous: 8,
      firstPlayAt: DateTime(2026, 11, 20),
    );
    expect(hidden.delta, isNull);
    final allTime = buildSongsPlayed(
      period: StatsPeriod.allTime,
      now: now,
      current: 20,
      previous: null,
      firstPlayAt: DateTime(2026, 10, 1),
    );
    expect(allTime.delta, isNull);
    final same = buildSongsPlayed(
      period: StatsPeriod.year,
      now: now,
      current: 5,
      previous: 5,
      firstPlayAt: DateTime(2024, 1, 1),
    );
    expect(same.delta, 'Same as last year');
  });

  test('time of day peak and parts', () {
    final hourly = List<int>.filled(24, 0);
    hourly[20] = 60 * _min;
    hourly[21] = 20 * _min;
    hourly[8] = 10 * _min;
    hourly[2] = 10 * _min;
    final t = buildTimeOfDay(hourly)!;
    expect(t.eyebrow, 'You listen most around 8 PM');
    expect(t.hourly, hourly);
    expect(t.partsPercent, [10, 0, 80, 10]);
    expect(t.partsPercent.fold<int>(0, (a, b) => a + b), 100);
    expect(t.highlighted, 2);
  });

  test('time of day parts sum to 100 and the earliest peak wins', () {
    final hourly = List<int>.filled(24, 0);
    hourly[0] = 1;
    hourly[7] = 1;
    hourly[13] = 1;
    final t = buildTimeOfDay(hourly)!;
    expect(t.eyebrow, 'You listen most around 12 AM');
    expect(t.partsPercent.fold<int>(0, (a, b) => a + b), 100);
    // Morning, afternoon and night tie: the first part wins.
    expect(t.highlighted, 0);
  });

  test('time of day is null without listening', () {
    expect(buildTimeOfDay(List<int>.filled(24, 0)), isNull);
  });
}
