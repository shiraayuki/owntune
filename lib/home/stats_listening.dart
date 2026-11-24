/// View models for the Listening time, Streak, Songs played and Time of Day
/// cards of the Stats page.
///
/// Pure Dart. Days and months are walked with calendar constructors, never by
/// adding a `Duration`, so a DST change cannot skip or repeat a day.
library;

import 'stats_period.dart';
import 'stats_repository.dart';

/// One bar of the listening chart. [label] is null for unlabelled bars,
/// [future] marks a slot after `now` (drawn empty).
class ChartBar {
  const ChartBar({this.label, required this.listenedMs, this.future = false});

  final String? label;
  final int listenedMs;
  final bool future;
}

class ListeningCard {
  const ListeningCard({
    required this.eyebrow,
    required this.total,
    required this.delta,
    required this.bars,
    required this.maxMs,
    required this.avgMs,
    required this.avgLabel,
  });

  final String eyebrow;
  final String total;
  final String? delta;
  final List<ChartBar> bars;

  /// The largest bar value, 0 without data.
  final int maxMs;

  /// Mean of the elapsed bars that have listening time, 0 when there are none.
  final int avgMs;
  final String avgLabel;
}

/// Whether the delta line may be shown: not for All Time, and only when the
/// history covers the whole previous range.
bool _deltaVisible(StatsPeriod period, DateTime now, DateTime? firstPlayAt) {
  final previous = previousRange(period, now);
  if (previous == null || firstPlayAt == null) return false;
  return !firstPlayAt.isAfter(previous.from);
}

int _sum(List<ListeningBucket> buckets) =>
    buckets.fold<int>(0, (sum, b) => sum + b.listenedMs);

const _weekLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _monthLabels = [
  'J',
  'F',
  'M',
  'A',
  'M',
  'J',
  'J',
  'A',
  'S',
  'O',
  'N',
  'D',
];
const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

ListeningCard buildListeningCard({
  required StatsPeriod period,
  required DateTime now,
  required List<ListeningBucket> buckets,
  required List<ListeningBucket>? previousBuckets,
  required DateTime? firstPlayAt,
}) {
  final byDay = <DateTime, int>{};
  final byMonth = <DateTime, int>{};
  for (final b in buckets) {
    final day = DateTime(b.start.year, b.start.month, b.start.day);
    byDay[day] = (byDay[day] ?? 0) + b.listenedMs;
    final month = DateTime(b.start.year, b.start.month);
    byMonth[month] = (byMonth[month] ?? 0) + b.listenedMs;
  }
  final today = DateTime(now.year, now.month, now.day);
  final thisMonth = DateTime(now.year, now.month);

  final bars = <ChartBar>[];
  switch (period) {
    case StatsPeriod.week:
      final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
      for (var i = 0; i < 7; i++) {
        final day = DateTime(monday.year, monday.month, monday.day + i);
        bars.add(
          ChartBar(
            label: _weekLabels[i],
            listenedMs: byDay[day] ?? 0,
            future: day.isAfter(today),
          ),
        );
      }
    case StatsPeriod.month:
      final days = DateTime(now.year, now.month + 1, 0).day;
      for (var d = 1; d <= days; d++) {
        final day = DateTime(now.year, now.month, d);
        bars.add(
          ChartBar(
            label: d % 7 == 1 ? '$d' : null,
            listenedMs: byDay[day] ?? 0,
            future: day.isAfter(today),
          ),
        );
      }
    case StatsPeriod.year:
      for (var m = 1; m <= 12; m++) {
        final month = DateTime(now.year, m);
        bars.add(
          ChartBar(
            label: _monthLabels[m - 1],
            listenedMs: byMonth[month] ?? 0,
            future: month.isAfter(thisMonth),
          ),
        );
      }
    case StatsPeriod.allTime:
      final first = firstPlayAt ?? now;
      final firstMonth = DateTime(first.year, first.month);
      final months =
          (now.year - first.year) * 12 + (now.month - first.month) + 1;
      if (months <= 24) {
        for (var i = 0; i < months; i++) {
          final month = DateTime(firstMonth.year, firstMonth.month + i);
          final edge = i == 0 || i == months - 1;
          bars.add(
            ChartBar(
              label: edge
                  ? '${_monthNames[month.month - 1]} ${month.year}'
                  : null,
              listenedMs: byMonth[month] ?? 0,
            ),
          );
        }
      } else {
        final years = now.year - first.year + 1;
        for (var i = 0; i < years; i++) {
          final year = first.year + i;
          var ms = 0;
          for (final entry in byMonth.entries) {
            if (entry.key.year == year) ms += entry.value;
          }
          final edge = i == 0 || i == years - 1;
          bars.add(ChartBar(label: edge ? '$year' : null, listenedMs: ms));
        }
      }
  }

  var maxMs = 0;
  var elapsedSum = 0;
  var elapsedWithData = 0;
  for (final bar in bars) {
    if (bar.listenedMs > maxMs) maxMs = bar.listenedMs;
    if (!bar.future && bar.listenedMs > 0) {
      elapsedSum += bar.listenedMs;
      elapsedWithData++;
    }
  }
  final avgMs = elapsedWithData == 0
      ? 0
      : (elapsedSum / elapsedWithData).round();

  String? delta;
  if (previousBuckets != null && _deltaVisible(period, now, firstPlayAt)) {
    delta = listeningDelta(_sum(buckets), _sum(previousBuckets), period);
  }

  return ListeningCard(
    eyebrow: 'Listening time · ${periodPhrase(period)}',
    total: formatListening(_sum(buckets)),
    delta: delta,
    bars: bars,
    maxMs: maxMs,
    avgMs: avgMs,
    avgLabel: 'avg ${formatListening(avgMs)}',
  );
}

class StreakCard {
  const StreakCard({required this.days, required this.last7});

  final int days;

  /// The last 7 days ending today, oldest first; true where a play happened.
  final List<bool> last7;

  String get label => days == 1 ? '1 day' : '$days days';
}

/// A day counts when it has at least one counted play. The streak ends today,
/// or yesterday while today has no play yet.
StreakCard buildStreak({
  required List<ListeningBucket> allDays,
  required DateTime now,
}) {
  final played = <DateTime>{
    for (final b in allDays)
      if (b.plays > 0) DateTime(b.start.year, b.start.month, b.start.day),
  };
  final today = DateTime(now.year, now.month, now.day);
  var cursor = played.contains(today)
      ? today
      : DateTime(today.year, today.month, today.day - 1);
  var days = 0;
  while (played.contains(cursor)) {
    days++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  final last7 = [
    for (var i = 6; i >= 0; i--)
      played.contains(DateTime(today.year, today.month, today.day - i)),
  ];
  return StreakCard(days: days, last7: last7);
}

class SongsPlayedCard {
  const SongsPlayedCard({required this.count, required this.delta});

  final int count;
  final String? delta;
}

SongsPlayedCard buildSongsPlayed({
  required StatsPeriod period,
  required DateTime now,
  required int current,
  required int? previous,
  required DateTime? firstPlayAt,
}) {
  String? delta;
  if (previous != null && _deltaVisible(period, now, firstPlayAt)) {
    delta = countDelta(current, previous, period);
  }
  return SongsPlayedCard(count: current, delta: delta);
}

class TimeOfDayCard {
  const TimeOfDayCard({
    required this.hourly,
    required this.eyebrow,
    required this.partsPercent,
    required this.highlighted,
  });

  /// Listening time per local hour, 24 values.
  final List<int> hourly;
  final String eyebrow;

  /// Percent of listening time in Morning (5-11), Afternoon (12-17),
  /// Evening (18-23) and Night (0-4); sums to 100.
  final List<int> partsPercent;

  /// Index of the largest part (the earliest wins a tie).
  final int highlighted;
}

/// `null` when there is no listening at all.
TimeOfDayCard? buildTimeOfDay(List<int> hourly) {
  if (hourly.fold<int>(0, (a, b) => a + b) <= 0) return null;
  var peak = 0;
  for (var h = 1; h < hourly.length; h++) {
    if (hourly[h] > hourly[peak]) peak = h;
  }
  int range(int from, int to) {
    var sum = 0;
    for (var h = from; h <= to; h++) {
      sum += hourly[h];
    }
    return sum;
  }

  final parts = [range(5, 11), range(12, 17), range(18, 23), range(0, 4)];
  var highlighted = 0;
  for (var i = 1; i < parts.length; i++) {
    if (parts[i] > parts[highlighted]) highlighted = i;
  }
  return TimeOfDayCard(
    hourly: hourly,
    eyebrow: 'You listen most around ${hourLabel(peak)}',
    partsPercent: largestRemainderPercents(parts),
    highlighted: highlighted,
  );
}
