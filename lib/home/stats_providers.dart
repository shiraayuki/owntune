import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/home/stats_listening.dart';
import 'package:owntune/home/stats_period.dart';
import 'package:owntune/home/stats_rankings.dart';
import 'package:owntune/home/stats_repository.dart';

/// The selected period chip. Lives for the session only.
class StatsPeriodController extends Notifier<StatsPeriod> {
  @override
  StatsPeriod build() => StatsPeriod.week;

  void select(StatsPeriod period) => state = period;
}

final statsPeriodProvider =
    NotifierProvider<StatsPeriodController, StatsPeriod>(
      StatsPeriodController.new,
    );

/// The size of the library's audio and cover files; run again whenever the
/// set of files changes (not on a play count or a tag edit).
final storageBytesProvider = FutureProvider<int>((ref) {
  ref.watch(
    tracksProvider.select(
      (songs) => switch (songs.value) {
        null => null,
        final list => Object.hashAll([
          for (final t in list) Object.hash(t.fileName, t.coverFile),
        ]),
      },
    ),
  );
  return ref.watch(trackRepositoryProvider).storageBytes();
});

/// Everything the Stats page shows.
///
/// With [enoughHistory] false only [library] is set. With [historyError] set
/// the history sections are null as well; [library] always renders.
class StatsView {
  const StatsView({
    required this.enoughHistory,
    this.listening,
    this.streak,
    this.songsPlayed,
    this.tops,
    this.timeOfDay,
    this.genres,
    this.recap,
    required this.library,
    this.mostPlayed = const [],
    this.historyError,
  });

  final bool enoughHistory;
  final ListeningCard? listening;
  final StreakCard? streak;
  final SongsPlayedCard? songsPlayed;
  final TopLists? tops;
  final TimeOfDayCard? timeOfDay;
  final GenreMix? genres;
  final MonthRecap? recap;
  final LibraryOverview library;
  final List<RankRow> mostPlayed;
  final Object? historyError;
}

/// Fewer counted plays than this in the whole history: not enough to show.
const statsMinPlays = 5;

typedef _Range = ({DateTime from, DateTime to});
typedef _BucketRange = ({
  DateTime from,
  DateTime to,
  StatsBucket bucket,
  bool countedOnly,
});

// Every stream is keyed by its (day-granular) bounds: it stays the same within
// a day and playback's five-second updates cannot restart it.
final _totalsProvider = StreamProvider.autoDispose
    .family<List<TrackTotal>, _Range>(
      (ref, r) => ref
          .watch(statsRepositoryProvider)
          .watchTrackTotals(from: r.from, to: r.to),
    );

final _bucketsProvider = StreamProvider.autoDispose
    .family<List<ListeningBucket>, _BucketRange>(
      (ref, r) => ref
          .watch(statsRepositoryProvider)
          .watchListeningBuckets(
            from: r.from,
            to: r.to,
            bucket: r.bucket,
            countedOnly: r.countedOnly,
          ),
    );

/// The rows of one local day, keyed by its midnight.
final _dayRowsProvider = StreamProvider.autoDispose
    .family<List<StatsPlayRow>, DateTime>(
      (ref, day) => ref.watch(statsRepositoryProvider).watchRowsOfDay(day: day),
    );

final _countedPlaysProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(statsRepositoryProvider).watchCountedPlays(),
);

final _hourlyProvider = StreamProvider.autoDispose.family<List<int>, _Range>(
  (ref, r) =>
      ref.watch(statsRepositoryProvider).watchHourly(from: r.from, to: r.to),
);

final _trackHistoryProvider =
    StreamProvider.autoDispose<Map<int, ({DateTime first, int counted})>>(
      (ref) => ref.watch(statsRepositoryProvider).watchTrackHistory(),
    );

final _firstPlayAtProvider = StreamProvider.autoDispose<DateTime?>(
  (ref) => ref.watch(statsRepositoryProvider).watchFirstPlayAt(),
);

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

int _sumListened(List<ListeningBucket> buckets) =>
    buckets.fold<int>(0, (sum, b) => sum + b.listenedMs);

int _sumTotalPlays(List<TrackTotal> totals) =>
    totals.fold<int>(0, (sum, t) => sum + t.plays);

/// The content of the Stats sub-tab for the chosen period. Loading until the
/// library, the playlists and every history stream have values. A failing
/// history becomes [StatsView.historyError], so Your Library still renders; a
/// failing library or playlist list is an error.
///
/// The streams are keyed by days: the current ranges end at the next local
/// midnight, so they stay the same within a day and move on the first rebuild
/// after midnight. The previous range is cut exactly at
/// `previousRange(period, now).to`: its whole days come from day-keyed streams
/// up to the comparison day's midnight, and of that day only the rows that
/// started before the cut are added in Dart.
final statsProvider = Provider<AsyncValue<StatsView>>((ref) {
  final period = ref.watch(statsPeriodProvider);
  final library = ref.watch(libraryProvider);
  final playlists = ref.watch(playlistsProvider);
  final storage = ref.watch(storageBytesProvider);
  final now = ref.watch(clockProvider)();

  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(now.year, now.month, now.day + 1);
  final monthStart = DateTime(now.year, now.month);
  final previousMonthStart = DateTime(now.year, now.month - 1);
  final from = period == StatsPeriod.allTime
      ? _epoch
      : currentRange(period, today).from;
  // The exact previous range, and its whole days up to the comparison day.
  final previousExact = previousRange(period, now);
  final cutDay = previousExact == null
      ? null
      : DateTime(
          previousExact.to.year,
          previousExact.to.month,
          previousExact.to.day,
        );
  final _Range? previous = previousExact == null
      ? null
      : (from: previousExact.from, to: cutDay!);
  final chartBucket = switch (period) {
    StatsPeriod.week || StatsPeriod.month => StatsBucket.day,
    StatsPeriod.year || StatsPeriod.allTime => StatsBucket.month,
  };

  final current = ref.watch(_totalsProvider((from: from, to: end)));
  final buckets = ref.watch(
    _bucketsProvider((
      from: from,
      to: end,
      bucket: chartBucket,
      countedOnly: false,
    )),
  );
  final hourly = ref.watch(_hourlyProvider((from: from, to: end)));
  final previousTotals = previous == null
      ? null
      : ref.watch(_totalsProvider(previous));
  final previousBuckets = previous == null
      ? null
      : ref.watch(
          _bucketsProvider((
            from: previous.from,
            to: previous.to,
            bucket: chartBucket,
            countedOnly: false,
          )),
        );
  final previousDayRows = cutDay == null
      ? null
      : ref.watch(_dayRowsProvider(cutDay));
  // The streak only needs the days with a counted play.
  final allDays = ref.watch(
    _bucketsProvider((
      from: _epoch,
      to: end,
      bucket: StatsBucket.day,
      countedOnly: true,
    )),
  );
  final countedPlays = ref.watch(_countedPlaysProvider);
  final month = ref.watch(_totalsProvider((from: monthStart, to: end)));
  final monthDays = ref.watch(
    _bucketsProvider((
      from: monthStart,
      to: end,
      bucket: StatsBucket.day,
      countedOnly: false,
    )),
  );
  final previousMonth = ref.watch(
    _bucketsProvider((
      from: previousMonthStart,
      to: monthStart,
      bucket: StatsBucket.month,
      countedOnly: false,
    )),
  );
  final trackHistory = ref.watch(_trackHistoryProvider);
  final firstPlay = ref.watch(_firstPlayAtProvider);

  for (final source in [library, playlists]) {
    if (source.hasError) {
      return AsyncError(source.error!, source.stackTrace ?? StackTrace.empty);
    }
  }
  if (!library.hasValue || !playlists.hasValue) return const AsyncLoading();

  final histories = <AsyncValue<Object?>>[
    current,
    buckets,
    hourly,
    ?previousTotals,
    ?previousBuckets,
    ?previousDayRows,
    allDays,
    countedPlays,
    month,
    monthDays,
    previousMonth,
    trackHistory,
    firstPlay,
  ];
  for (final history in histories) {
    if (!history.hasValue && !history.hasError) return const AsyncLoading();
  }

  final overview = buildLibraryOverview(
    library: library.requireValue,
    playlistCount: playlists.requireValue.length,
    storageBytes: storage.value,
  );
  final failed = histories.where((h) => h.hasError).firstOrNull;
  if (failed != null) {
    return AsyncData(
      StatsView(
        enoughHistory: true,
        library: overview,
        historyError: failed.error,
      ),
    );
  }

  if (countedPlays.requireValue < statsMinPlays) {
    return AsyncData(StatsView(enoughHistory: false, library: overview));
  }

  final lib = library.requireValue;
  final firstPlayAt = firstPlay.requireValue;
  final totals = current.requireValue;
  final monthDayBuckets = monthDays.requireValue;
  final previousMonthMs =
      firstPlayAt == null || firstPlayAt.isAfter(previousMonthStart)
      ? null
      : _sumListened(previousMonth.requireValue);

  // The previous range: its whole days plus the part of the comparison day
  // before the exact cut.
  List<ListeningBucket>? previousListening;
  int? previousPlays;
  if (previousExact != null) {
    var partMs = 0;
    var partPlays = 0;
    for (final row in previousDayRows!.requireValue) {
      if (!row.startedAt.isBefore(previousExact.to)) continue;
      partMs += row.listenedMs;
      if (row.counted) partPlays++;
    }
    previousListening = [
      ...previousBuckets!.requireValue,
      ListeningBucket(cutDay!, partMs, partPlays),
    ];
    previousPlays = _sumTotalPlays(previousTotals!.requireValue) + partPlays;
  }

  return AsyncData(
    StatsView(
      enoughHistory: true,
      listening: buildListeningCard(
        period: period,
        now: now,
        buckets: buckets.requireValue,
        previousBuckets: previousListening,
        firstPlayAt: firstPlayAt,
      ),
      streak: buildStreak(allDays: allDays.requireValue, now: now),
      songsPlayed: buildSongsPlayed(
        period: period,
        now: now,
        current: _sumTotalPlays(totals),
        previous: previousPlays,
        firstPlayAt: firstPlayAt,
      ),
      tops: buildTopLists(library: lib, totals: totals),
      timeOfDay: buildTimeOfDay(hourly.requireValue),
      genres: buildGenres(library: lib, totals: totals, period: period),
      recap: buildRecap(
        now: now,
        library: lib,
        month: month.requireValue,
        monthListenedMs: _sumListened(monthDayBuckets),
        monthDays: monthDayBuckets.where((b) => b.listenedMs > 0).length,
        previousMonthListenedMs: previousMonthMs,
        trackHistory: trackHistory.requireValue,
      ),
      library: overview,
      mostPlayed: buildMostPlayed(lib),
    ),
  );
});
