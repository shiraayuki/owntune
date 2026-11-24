import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/home/stats_period.dart';

void main() {
  test('week range starts on Monday', () {
    final now = DateTime(2026, 11, 25, 20);
    final current = currentRange(StatsPeriod.week, now);
    expect(current.from, DateTime(2026, 11, 23));
    expect(current.to, now);
    final previous = previousRange(StatsPeriod.week, now)!;
    expect(previous.from, DateTime(2026, 11, 16));
    expect(previous.to, DateTime(2026, 11, 18, 20));
  });

  test('week range on a Monday and a Sunday', () {
    final monday = DateTime(2026, 11, 23, 0, 30);
    expect(currentRange(StatsPeriod.week, monday).from, DateTime(2026, 11, 23));
    final sunday = DateTime(2026, 11, 29, 23, 59);
    expect(currentRange(StatsPeriod.week, sunday).from, DateTime(2026, 11, 23));
  });

  test('week range across a DST change', () {
    // Europe switches on 2026-10-25; the result is the same in any zone
    // because only calendar arithmetic is used.
    final now = DateTime(2026, 10, 28, 9, 15);
    final current = currentRange(StatsPeriod.week, now);
    expect(current.from, DateTime(2026, 10, 26));
    expect(current.from.hour, 0);
    final previous = previousRange(StatsPeriod.week, now)!;
    expect(previous.from, DateTime(2026, 10, 19));
    expect(previous.from.hour, 0);
    expect(previous.to, DateTime(2026, 10, 21, 9, 15));
    expect(previous.to.hour, 9);

    final sunday = DateTime(2026, 11, 1, 10);
    expect(currentRange(StatsPeriod.week, sunday).from, DateTime(2026, 10, 26));
    expect(currentRange(StatsPeriod.week, sunday).from.hour, 0);
  });

  test('month range', () {
    final now = DateTime(2026, 11, 24, 18, 30);
    final current = currentRange(StatsPeriod.month, now);
    expect(current.from, DateTime(2026, 11));
    expect(current.to, now);
    final previous = previousRange(StatsPeriod.month, now)!;
    expect(previous.from, DateTime(2026, 10));
    expect(previous.to, DateTime(2026, 10, 24, 18, 30));
  });

  test('month previous range is capped at the end of the shorter month', () {
    final now = DateTime(2026, 3, 31, 12);
    final previous = previousRange(StatsPeriod.month, now)!;
    expect(previous.from, DateTime(2026, 2));
    expect(previous.to, DateTime(2026, 3));
  });

  test('month previous range across a year boundary', () {
    final now = DateTime(2026, 1, 15, 8);
    final previous = previousRange(StatsPeriod.month, now)!;
    expect(previous.from, DateTime(2025, 12));
    expect(previous.to, DateTime(2025, 12, 15, 8));
  });

  test('year previous range is the same elapsed span', () {
    final now = DateTime(2026, 11, 24, 18, 30);
    final current = currentRange(StatsPeriod.year, now);
    expect(current.from, DateTime(2026));
    expect(current.to, now);
    final previous = previousRange(StatsPeriod.year, now)!;
    expect(previous.from, DateTime(2025));
    expect(previous.to, DateTime(2025, 11, 24, 18, 30));
  });

  test('all time has no previous range', () {
    final now = DateTime(2026, 11, 24, 18);
    final first = DateTime(2026, 9, 3, 7, 5);
    expect(previousRange(StatsPeriod.allTime, now), isNull);
    final current = currentRange(StatsPeriod.allTime, now, firstPlayAt: first);
    expect(current.from, first);
    expect(current.to, now);
    expect(currentRange(StatsPeriod.allTime, now).from, now);
  });

  test('phrases', () {
    expect(periodPhrase(StatsPeriod.week), 'this week');
    expect(periodPhrase(StatsPeriod.month), 'this month');
    expect(periodPhrase(StatsPeriod.year), 'this year');
    expect(periodPhrase(StatsPeriod.allTime), 'all time');
    expect(lastPhrase(StatsPeriod.week), 'last week');
    expect(lastPhrase(StatsPeriod.month), 'last month');
    expect(lastPhrase(StatsPeriod.year), 'last year');
  });

  test('formatListening boundaries', () {
    expect(formatListening(0), '0 min');
    expect(formatListening(1), '< 1 min');
    expect(formatListening(59999), '< 1 min');
    expect(formatListening(60000), '1 min');
    expect(formatListening(5 * 60000), '5 min');
    expect(formatListening(59 * 60000), '59 min');
    expect(formatListening(3600000), '1 h 00 min');
    expect(formatListening(6 * 3600000 + 5 * 60000), '6 h 05 min');
    expect(formatListening(22320000), '6 h 12 min');
  });

  test('deltas', () {
    const min = 60000;
    expect(
      listeningDelta(148 * min, 100 * min, StatsPeriod.week),
      '+48 min vs. last week',
    );
    expect(
      listeningDelta(100 * min, 165 * min, StatsPeriod.month),
      '−1 h 05 min vs. last month',
    );
    expect(
      listeningDelta(5 * min, 5 * min, StatsPeriod.year),
      'Same as last year',
    );
    expect(listeningDelta(5, 5, StatsPeriod.allTime), isNull);
    expect(countDelta(20, 8, StatsPeriod.week), '+12 vs. last week');
    expect(countDelta(2, 5, StatsPeriod.month), '−3 vs. last month');
    expect(countDelta(4, 4, StatsPeriod.year), 'Same as last year');
    expect(countDelta(4, 1, StatsPeriod.allTime), isNull);
  });

  test('a listening difference under a minute reads Same as', () {
    const min = 60000;
    expect(
      listeningDelta(10 * min + 59999, 10 * min, StatsPeriod.week),
      'Same as last week',
    );
    expect(
      listeningDelta(10 * min, 10 * min + 59999, StatsPeriod.month),
      'Same as last month',
    );
    expect(
      listeningDelta(11 * min, 10 * min, StatsPeriod.week),
      '+1 min vs. last week',
    );
  });

  test('largest remainder sums to 100', () {
    expect(largestRemainderPercents([1, 1, 1]), [34, 33, 33]);
    expect(largestRemainderPercents([0, 0]), [0, 0]);
    expect(largestRemainderPercents([]), <int>[]);
    expect(largestRemainderPercents([5]), [100]);
    expect(largestRemainderPercents([1, 2]), [33, 67]);
    final values = [7, 13, 29, 3, 41, 11];
    expect(largestRemainderPercents(values).reduce((a, b) => a + b), 100);
  });

  test('hour labels', () {
    expect(hourLabel(0), '12 AM');
    expect(hourLabel(1), '1 AM');
    expect(hourLabel(11), '11 AM');
    expect(hourLabel(12), '12 PM');
    expect(hourLabel(13), '1 PM');
    expect(hourLabel(20), '8 PM');
    expect(hourLabel(23), '11 PM');
  });
}
