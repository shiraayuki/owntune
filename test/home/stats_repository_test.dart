import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/home/stats_repository.dart';

void main() {
  late AppDatabase db;
  late StatsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = StatsRepository(db);
  });

  tearDown(() => db.close());

  Future<void> play(
    int trackId,
    DateTime at, {
    bool counted = true,
    int listenedMs = 40000,
  }) => db
      .into(db.plays)
      .insert(
        PlaysCompanion.insert(
          trackId: trackId,
          startedAt: at,
          listenedMs: listenedMs,
          counted: counted,
        ),
      );

  test(
    'track totals count counted plays and sum all listening in range',
    () async {
      final from = DateTime(2026, 11, 1);
      final to = DateTime(2026, 12, 1);
      await play(1, DateTime(2026, 11, 3, 10), listenedMs: 1000);
      await play(1, DateTime(2026, 11, 4, 10), listenedMs: 2000);
      await play(1, DateTime(2026, 11, 5, 10), counted: false, listenedMs: 500);
      await play(2, from, listenedMs: 700); // at from: included
      await play(2, to, listenedMs: 9999); // at to: excluded
      await play(3, DateTime(2026, 10, 31, 23), listenedMs: 9999); // before

      final totals = await repo.watchTrackTotals(from: from, to: to).first;

      expect(totals..sort((a, b) => a.trackId.compareTo(b.trackId)), [
        const TrackTotal(1, 2, 3500),
        const TrackTotal(2, 1, 700),
      ]);
    },
  );

  test('days are bucketed in local time', () async {
    await play(1, DateTime(2026, 11, 10, 23, 59), listenedMs: 1000);
    await play(1, DateTime(2026, 11, 11, 0, 1), listenedMs: 2000);
    await play(2, DateTime(2026, 11, 11, 12), counted: false, listenedMs: 300);

    final buckets = await repo
        .watchListeningBuckets(
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 12, 1),
          bucket: StatsBucket.day,
        )
        .first;

    expect(buckets, [
      ListeningBucket(DateTime(2026, 11, 10), 1000, 1),
      ListeningBucket(DateTime(2026, 11, 11), 2300, 1),
    ]);
    expect(buckets.every((b) => !b.start.isUtc), isTrue);
  });

  test('months are bucketed in local time', () async {
    await play(1, DateTime(2026, 10, 31, 23, 59), listenedMs: 1000);
    await play(1, DateTime(2026, 11, 1, 0, 1), listenedMs: 2000);
    await play(1, DateTime(2026, 11, 30, 23, 59), listenedMs: 4000);

    final buckets = await repo
        .watchListeningBuckets(
          from: DateTime(2026, 1, 1),
          to: DateTime(2027, 1, 1),
          bucket: StatsBucket.month,
        )
        .first;

    expect(buckets, [
      ListeningBucket(DateTime(2026, 10), 1000, 1),
      ListeningBucket(DateTime(2026, 11), 6000, 2),
    ]);
  });

  test('hourly has 24 entries with listening per local hour', () async {
    await play(1, DateTime(2026, 11, 10, 0, 30), listenedMs: 1000);
    await play(1, DateTime(2026, 11, 11, 0, 5), listenedMs: 2000);
    await play(1, DateTime(2026, 11, 11, 20, 59), listenedMs: 5000);
    await play(1, DateTime(2026, 12, 1, 20), listenedMs: 9999); // at to

    final hourly = await repo
        .watchHourly(from: DateTime(2026, 11, 1), to: DateTime(2026, 12, 1))
        .first;

    expect(hourly, hasLength(24));
    expect(hourly[0], 3000);
    expect(hourly[20], 5000);
    expect(hourly.fold<int>(0, (a, b) => a + b), 8000);
  });

  test(
    'track history gives first counted play and counted rows per track',
    () async {
      await play(1, DateTime(2026, 11, 5, 10));
      await play(1, DateTime(2026, 11, 3, 10));
      await play(1, DateTime(2026, 11, 1, 10), counted: false);
      await play(2, DateTime(2026, 11, 2, 10));
      await play(3, DateTime(2026, 11, 2, 11), counted: false);

      final history = await repo.watchTrackHistory().first;

      expect(history, {
        1: (first: DateTime(2026, 11, 3, 10), counted: 2),
        2: (first: DateTime(2026, 11, 2, 10), counted: 1),
      });
    },
  );

  test('first play is the earliest row', () async {
    expect(await repo.watchFirstPlayAt().first, isNull);

    await play(1, DateTime(2026, 11, 5, 10));
    await play(2, DateTime(2026, 11, 2, 10), counted: false);

    expect(await repo.watchFirstPlayAt().first, DateTime(2026, 11, 2, 10));
  });

  test('an update outside the range does not re-emit', () async {
    await play(1, DateTime(2026, 11, 10, 10));
    await play(2, DateTime(2026, 12, 20, 10)); // the open row, outside
    final emissions = <List<TrackTotal>>[];
    final sub = repo
        .watchTrackTotals(
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 12, 1),
        )
        .listen(emissions.add);
    await pumpEventQueue();
    expect(emissions, hasLength(1));

    await (db.update(db.plays)..where((p) => p.trackId.equals(2))).write(
      const PlaysCompanion(listenedMs: Value(45000)),
    );
    await pumpEventQueue();

    expect(emissions, hasLength(1));
    await sub.cancel();
  });

  test('counted plays count only counted rows and emit on a change', () async {
    await play(1, DateTime(2026, 11, 3, 10));
    await play(1, DateTime(2026, 11, 4, 10), counted: false);
    await play(2, DateTime(2026, 11, 5, 10));
    final emissions = <int>[];
    final sub = repo.watchCountedPlays().listen(emissions.add);
    await pumpEventQueue();
    expect(emissions, [2]);

    // A growing uncounted row does not change the count.
    await (db.update(db.plays)..where((p) => p.counted.equals(false))).write(
      const PlaysCompanion(listenedMs: Value(45000)),
    );
    await pumpEventQueue();
    expect(emissions, [2]);

    await play(3, DateTime(2026, 11, 6, 10));
    await pumpEventQueue();
    expect(emissions, [2, 3]);
    await sub.cancel();
  });

  test('counted-only buckets leave out days without a counted play', () async {
    await play(1, DateTime(2026, 11, 10, 10), listenedMs: 1000);
    await play(1, DateTime(2026, 11, 10, 11), counted: false, listenedMs: 50);
    await play(2, DateTime(2026, 11, 11, 12), counted: false, listenedMs: 300);

    final buckets = await repo
        .watchListeningBuckets(
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 12, 1),
          bucket: StatsBucket.day,
          countedOnly: true,
        )
        .first;

    expect(buckets, [ListeningBucket(DateTime(2026, 11, 10), 1000, 1)]);
  });

  test('rows of a day are that local day only, oldest first', () async {
    await play(1, DateTime(2026, 11, 17, 23, 59), listenedMs: 1);
    await play(1, DateTime(2026, 11, 18, 18), listenedMs: 2000);
    await play(2, DateTime(2026, 11, 18, 0), counted: false, listenedMs: 300);
    await play(1, DateTime(2026, 11, 19), listenedMs: 4);

    final rows = await repo
        .watchRowsOfDay(day: DateTime(2026, 11, 18, 12))
        .first;

    expect(rows, [
      (startedAt: DateTime(2026, 11, 18), counted: false, listenedMs: 300),
      (startedAt: DateTime(2026, 11, 18, 18), counted: true, listenedMs: 2000),
    ]);
  });
}
