import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/home/stats_listening.dart';
import 'package:owntune/home/stats_period.dart';
import 'package:owntune/home/stats_rankings.dart';
import 'package:owntune/home/stats_repository.dart';
import 'package:owntune/library/library.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AppDatabase db;
  late TrackRepository tracks;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('owntune_stats_it');
    final storage = LibraryStorage(Directory('${tmp.path}/library'));
    await storage.ensure();
    db = AppDatabase(NativeDatabase(File('${tmp.path}/owntune.sqlite')));
    tracks = TrackRepository(db, storage);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('Stats on the real database', (t) async {
    // Tuesday; the week started on Monday the 23rd.
    final now = DateTime(2026, 11, 24, 12);
    for (var i = 1; i <= 2; i++) {
      await tracks.insert(
        TracksCompanion.insert(
          fileName: 'file$i.mp3',
          originalName: 'song$i.mp3',
          contentHash: 'hash$i',
          title: Value('Song $i'),
          artist: const Value('Artist A'),
          album: const Value('Album A'),
          genre: const Value('Rock'),
          trackNumber: Value(i),
          durationMs: 180000,
          addedAt: now.subtract(const Duration(days: 10)),
          // The counter lives on the row; inserting plays does not move it.
          playCount: Value(i == 1 ? 3 : 1),
        ),
      );
    }
    final inserted = await tracks.watchAll().first;
    final song1 = inserted.firstWhere((s) => s.title == 'Song 1');
    final song2 = inserted.firstWhere((s) => s.title == 'Song 2');

    Future<void> play(
      int trackId,
      DateTime at, {
      required int listenedMs,
      required bool counted,
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

    // Monday: song 1 twice (counted), plus a skipped 20 s sample.
    await play(
      song1.id,
      DateTime(2026, 11, 23, 20),
      listenedMs: 180000,
      counted: true,
    );
    await play(
      song1.id,
      DateTime(2026, 11, 23, 21),
      listenedMs: 180000,
      counted: true,
    );
    await play(
      song2.id,
      DateTime(2026, 11, 23, 22),
      listenedMs: 20000,
      counted: false,
    );
    // Tuesday: song 1 and song 2 once each (counted).
    await play(
      song1.id,
      DateTime(2026, 11, 24, 9),
      listenedMs: 180000,
      counted: true,
    );
    await play(
      song2.id,
      DateTime(2026, 11, 24, 10),
      listenedMs: 180000,
      counted: true,
    );

    final repo = StatsRepository(db);
    final from = DateTime(2026, 11, 23);
    final to = DateTime(2026, 11, 25);
    final totals = await repo.watchTrackTotals(from: from, to: to).first;
    final buckets = await repo
        .watchListeningBuckets(from: from, to: to, bucket: StatsBucket.day)
        .first;
    final firstPlayAt = await repo.watchFirstPlayAt().first;
    final library = Library.from(await tracks.watchAll().first);

    final card = buildListeningCard(
      period: StatsPeriod.week,
      now: now,
      buckets: buckets,
      previousBuckets: const [],
      firstPlayAt: firstPlayAt,
    );
    // 4 x 3 min counted + 20 s uncounted = 12 min 20 s.
    expect(card.total, '12 min');
    expect(card.bars, hasLength(7));
    expect(card.bars.where((b) => b.listenedMs > 0), hasLength(2));
    expect(buckets.map((b) => b.start), [from, DateTime(2026, 11, 24)]);

    final songsPlayed = buildSongsPlayed(
      period: StatsPeriod.week,
      now: now,
      current: totals.fold<int>(0, (sum, t) => sum + t.plays),
      previous: null,
      firstPlayAt: firstPlayAt,
    );
    expect(songsPlayed.count, 4);

    final tops = buildTopLists(library: library, totals: totals);
    expect(tops.songs.first.title, 'Song 1');
    expect(tops.songs.first.playsLabel, '3 plays');
    expect(tops.artists.single.title, 'Artist A');
    expect(tops.artists.single.playsLabel, '4 plays');

    final streak = buildStreak(allDays: buckets, now: now);
    expect(streak.days, 2);
  });
}
