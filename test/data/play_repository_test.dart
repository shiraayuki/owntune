import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/play_repository.dart';

void main() {
  late AppDatabase db;
  late PlayRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = PlayRepository(db);
  });

  tearDown(() => db.close());

  test('insert then update keeps one row', () async {
    final startedAt = DateTime(2026, 11, 24, 20);
    final id = await repo.insert(
      trackId: 1,
      startedAt: startedAt,
      listenedMs: 1200,
      counted: false,
      sourceKind: 'album',
      sourceKey: 'a\u0000b',
    );
    await repo.update(id, listenedMs: 31000, counted: true);

    final rows = await db.select(db.plays).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, id);
    expect(rows.single.trackId, 1);
    expect(rows.single.startedAt, startedAt);
    expect(rows.single.listenedMs, 31000);
    expect(rows.single.counted, isTrue);
    expect(rows.single.sourceKind, 'album');
    expect(rows.single.sourceKey, 'a\u0000b');
  });
}
