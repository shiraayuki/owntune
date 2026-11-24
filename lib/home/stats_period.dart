/// Periods of the Stats page, their date ranges and the number formatting.
///
/// Pure Dart. Day boundaries are built with calendar constructors (never by
/// subtracting a `Duration`), so a DST change cannot shift them.
library;

enum StatsPeriod { week, month, year, allTime }

/// A half-open range `[from, to)`.
typedef DateRange = ({DateTime from, DateTime to});

/// The current range of [period]. For [StatsPeriod.allTime] it starts at
/// [firstPlayAt], or at [now] when there is no play yet.
DateRange currentRange(
  StatsPeriod period,
  DateTime now, {
  DateTime? firstPlayAt,
}) {
  switch (period) {
    case StatsPeriod.week:
      return (
        from: DateTime(now.year, now.month, now.day - (now.weekday - 1)),
        to: now,
      );
    case StatsPeriod.month:
      return (from: DateTime(now.year, now.month), to: now);
    case StatsPeriod.year:
      return (from: DateTime(now.year), to: now);
    case StatsPeriod.allTime:
      return (from: firstPlayAt ?? now, to: now);
  }
}

/// The same elapsed span one week, month or year earlier; `null` for
/// [StatsPeriod.allTime].
DateRange? previousRange(StatsPeriod period, DateTime now) {
  switch (period) {
    case StatsPeriod.week:
      return (
        from: DateTime(now.year, now.month, now.day - (now.weekday - 1) - 7),
        to: DateTime(
          now.year,
          now.month,
          now.day - 7,
          now.hour,
          now.minute,
          now.second,
          now.millisecond,
        ),
      );
    case StatsPeriod.month:
      final shifted = DateTime(
        now.year,
        now.month - 1,
        now.day,
        now.hour,
        now.minute,
        now.second,
        now.millisecond,
      );
      final endOfPreviousMonth = DateTime(now.year, now.month);
      return (
        from: DateTime(now.year, now.month - 1),
        to: shifted.isBefore(endOfPreviousMonth) ? shifted : endOfPreviousMonth,
      );
    case StatsPeriod.year:
      return (
        from: DateTime(now.year - 1),
        to: DateTime(
          now.year - 1,
          now.month,
          now.day,
          now.hour,
          now.minute,
          now.second,
          now.millisecond,
        ),
      );
    case StatsPeriod.allTime:
      return null;
  }
}

String periodPhrase(StatsPeriod period) => switch (period) {
  StatsPeriod.week => 'this week',
  StatsPeriod.month => 'this month',
  StatsPeriod.year => 'this year',
  StatsPeriod.allTime => 'all time',
};

String lastPhrase(StatsPeriod period) => switch (period) {
  StatsPeriod.week => 'last week',
  StatsPeriod.month => 'last month',
  StatsPeriod.year => 'last year',
  StatsPeriod.allTime => 'all time',
};

/// "6 h 05 min" from one hour, "5 min" from one minute, "< 1 min" below,
/// "0 min" at zero.
String formatListening(int ms) {
  if (ms <= 0) return '0 min';
  if (ms < 60000) return '< 1 min';
  final totalMinutes = ms ~/ 60000;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '$minutes min';
  return '$hours h ${minutes.toString().padLeft(2, '0')} min';
}

const _minus = '−';

String? _delta(int diff, String Function(int) format, StatsPeriod period) {
  if (period == StatsPeriod.allTime) return null;
  final last = lastPhrase(period);
  if (diff == 0) return 'Same as $last';
  final sign = diff > 0 ? '+' : _minus;
  return '$sign${format(diff.abs())} vs. $last';
}

/// Listening times less than a minute apart read "Same as …", never
/// "+< 1 min".
String? listeningDelta(int current, int previous, StatsPeriod period) =>
    _delta(_minuteDiff(current, previous), formatListening, period);

/// [current] − [previous], or 0 when they are less than a minute apart.
int _minuteDiff(int current, int previous) {
  final diff = current - previous;
  return diff.abs() < 60000 ? 0 : diff;
}

/// Whether two listening times count as the same: less than a minute apart.
bool sameListening(int a, int b) => _minuteDiff(a, b) == 0;

String? countDelta(int current, int previous, StatsPeriod period) =>
    _delta(current - previous, (n) => '$n', period);

/// Rounds [values] to whole percents that sum to 100 (largest remainder;
/// ties go to the earlier index). All zeros if the total is 0.
List<int> largestRemainderPercents(List<int> values) {
  final total = values.fold<int>(0, (a, b) => a + b);
  if (total <= 0) return List<int>.filled(values.length, 0);
  final result = [for (final v in values) v * 100 ~/ total];
  var left = 100 - result.fold<int>(0, (a, b) => a + b);
  final order = List<int>.generate(values.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = (values[b] * 100 % total).compareTo(
        values[a] * 100 % total,
      );
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  for (final i in order) {
    if (left <= 0) break;
    result[i]++;
    left--;
  }
  return result;
}

/// 0 -> "12 AM", 12 -> "12 PM", 13 -> "1 PM".
String hourLabel(int hour) {
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12 ${hour < 12 ? 'AM' : 'PM'}';
}
