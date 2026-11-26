import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/loudness_repository.dart';

void main() {
  late AppDatabase db;
  late LoudnessRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LoudnessRepository(db);
  });

  tearDown(() => db.close());

  Future<int> addTrack(String hash, DateTime addedAt) => db
      .into(db.tracks)
      .insert(
        TracksCompanion.insert(
          fileName: '$hash.mp3',
          originalName: '$hash.mp3',
          contentHash: hash,
          durationMs: 1000,
          addedAt: addedAt,
          title: Value(hash),
        ),
      );

  test('nextUnmeasured returns the newest track without a row', () async {
    await addTrack('old', DateTime(2026, 1, 1));
    final newest = await addTrack('new', DateTime(2026, 3, 1));
    final middle = await addTrack('mid', DateTime(2026, 2, 1));

    expect((await repo.nextUnmeasured(1))!.id, newest);
    await repo.saveMeasured(newest, -9);
    expect((await repo.nextUnmeasured(1))!.id, middle);
  });

  test(
    'nextUnmeasured skips tracks that failed with the current version',
    () async {
      final id = await addTrack('a', DateTime(2026, 1, 1));
      await repo.saveFailed(id, 1);

      expect(await repo.nextUnmeasured(1), isNull);
      expect((await repo.nextUnmeasured(2))!.id, id);
    },
  );

  test(
    'nextUnmeasured returns null when everything is measured or failed',
    () async {
      final a = await addTrack('a', DateTime(2026, 1, 1));
      final b = await addTrack('b', DateTime(2026, 1, 2));
      await repo.saveMeasured(a, -12);
      await repo.saveFailed(b, 1);

      expect(await repo.nextUnmeasured(1), isNull);
    },
  );

  test('saveMeasured clears an earlier failure', () async {
    final id = await addTrack('a', DateTime(2026, 1, 1));
    await repo.saveFailed(id, 1);
    await repo.saveMeasured(id, -9.5);

    expect(await repo.lufsOf(id), -9.5);
    final row = await db.select(db.trackLoudness).getSingle();
    expect(row.failedVersion, isNull);
  });

  test('saving for a deleted track writes nothing', () async {
    await repo.saveMeasured(99, -9);
    await repo.saveFailed(99, 1);

    expect(await db.select(db.trackLoudness).get(), isEmpty);
  });

  test('lufsOf is null for unmeasured and failed tracks', () async {
    final a = await addTrack('a', DateTime(2026, 1, 1));
    final b = await addTrack('b', DateTime(2026, 1, 2));
    await repo.saveFailed(b, 1);

    expect(await repo.lufsOf(a), isNull);
    expect(await repo.lufsOf(b), isNull);
  });
}
