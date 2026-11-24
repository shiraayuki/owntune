import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/player/queue_source.dart';

final _since = DateTime(2026, 1, 1);

void main() {
  late AppDatabase db;
  late HomeRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = HomeRepository(db);
  });

  tearDown(() => db.close());

  Future<void> play(
    int trackId,
    DateTime at, {
    bool counted = true,
    String? kind,
    String? key,
  }) => db
      .into(db.plays)
      .insert(
        PlaysCompanion.insert(
          trackId: trackId,
          startedAt: at,
          listenedMs: 40000,
          counted: counted,
          sourceKind: Value(kind),
          sourceKey: Value(key),
        ),
      );

  test('recent sources are distinct and newest first', () async {
    await play(1, DateTime(2026, 11, 24, 10), kind: 'playlist', key: '3');
    await play(2, DateTime(2026, 11, 24, 12), kind: 'playlist', key: '3');
    await play(3, DateTime(2026, 11, 24, 11), kind: 'album', key: 'a\u0000b');

    final recent = await repo.watchRecentSources(since: _since).first;

    expect(recent, [
      RecentSource(QueueSourceKind.playlist, '3', DateTime(2026, 11, 24, 12)),
      RecentSource(
        QueueSourceKind.album,
        'a\u0000b',
        DateTime(2026, 11, 24, 11),
      ),
    ]);
  });

  test('recent sources start at the since date', () async {
    await play(1, DateTime(2025, 12, 31, 23), kind: 'album', key: 'old');
    await play(2, DateTime(2026, 1, 1), kind: 'album', key: 'edge');

    final recent = await repo.watchRecentSources(since: _since).first;

    expect(recent.map((r) => r.key), ['edge']);
  });

  test('non-source kinds are excluded', () async {
    final at = DateTime(2026, 11, 24, 10);
    await play(1, at, kind: 'songs');
    await play(2, at, kind: 'search');
    await play(3, at, kind: 'queued');
    await play(4, at, kind: 'other', key: 'Rediscover');
    await play(5, at);

    expect(await repo.watchRecentSources(since: _since).first, isEmpty);
  });

  test('liked sources have no key', () async {
    await play(1, DateTime(2026, 11, 24, 10), kind: 'liked');

    expect(await repo.watchRecentSources(since: _since).first, [
      RecentSource(QueueSourceKind.liked, null, DateTime(2026, 11, 24, 10)),
    ]);
  });

  test('top tracks count only counted plays since the date', () async {
    final since = DateTime(2026, 11, 1);
    final inside = DateTime(2026, 11, 10);
    await play(1, inside);
    await play(1, inside.add(const Duration(hours: 1)));
    await play(1, inside.add(const Duration(hours: 2)));
    await play(1, inside, counted: false);
    await play(1, DateTime(2026, 10, 20));
    await play(2, inside.add(const Duration(days: 1)));
    await play(2, inside.add(const Duration(days: 2)));
    await play(2, inside.add(const Duration(days: 3)));

    final top = await repo.watchTopTracks(since: since).first;

    expect(top, [TrackPlayCount(2, 3), TrackPlayCount(1, 3)]);
  });

  test('streams re-emit after a new play row', () async {
    final emissions = <List<RecentSource>>[];
    final sub = repo.watchRecentSources(since: _since).listen(emissions.add);
    await pumpEventQueue();
    expect(emissions.last, isEmpty);

    await play(1, DateTime(2026, 11, 24, 10), kind: 'album', key: 'a\u0000b');
    await pumpEventQueue();

    expect(emissions, hasLength(2));
    expect(emissions.last.single.key, 'a\u0000b');
    await sub.cancel();
  });

  test('a play update that changes nothing shown does not re-emit', () async {
    final at = DateTime(2026, 11, 24, 10);
    await play(1, at, kind: 'album', key: 'a\u0000b');
    final recent = <List<RecentSource>>[];
    final top = <List<TrackPlayCount>>[];
    final subs = [
      repo.watchRecentSources(since: _since).listen(recent.add),
      repo.watchTopTracks(since: DateTime(2026, 11, 1)).listen(top.add),
    ];
    await pumpEventQueue();
    expect(recent, hasLength(1));
    expect(top, hasLength(1));

    // The player updates the open row's listened_ms while music plays.
    await (db.update(db.plays))
        .write(const PlaysCompanion(listenedMs: Value(45000)));
    await pumpEventQueue();

    expect(recent, hasLength(1));
    expect(top, hasLength(1));
    for (final sub in subs) {
      await sub.cancel();
    }
  });
}
