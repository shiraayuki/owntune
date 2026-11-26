import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/loudness_repository.dart';
import 'package:owntune/download/mp4_duration.dart';
import 'package:owntune/loudness/loudness_measurer.dart';
import 'package:owntune/loudness/loudness_meter.dart';
import 'package:owntune/src/rust/api/loudness.dart';
import 'package:owntune/src/rust/frb_generated.dart';

import 'support/fixtures.dart';

late Directory _fixtures;

String fixture(String name) {
  final file = File('${_fixtures.path}/$name');
  expect(file.existsSync(), isTrue, reason: 'missing fixture ${file.path}');
  return file.path;
}

Uint8List bytes(String name) => File(fixture(name)).readAsBytesSync();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
    _fixtures = fixturesDir();
  });

  Future<LoudnessResult> measure(String path) =>
      measureLoudness(path: path, job: newLoudnessJob());

  for (final name in ['tagged.mp3', 'tagged.m4a', 'dash.m4a']) {
    testWidgets('measures $name', (t) async {
      final r = await measure(fixture(name));
      expect(r.lufs, isNotNull, reason: r.message);
      expect(r.lufs!.isFinite, isTrue);
      expect(r.cancelled, isFalse);
    });
  }

  testWidgets('measures a joined SoundCloud-style download', (t) async {
    final dir = await Directory.systemTemp.createTemp('owntune-loudness');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/download.m4a');
    final builder = BytesBuilder()
      ..add(
        patchMp4Duration(
          bytes('hls_init.mp4'),
          const Duration(milliseconds: 1128),
        ),
      );
    for (var i = 0; i < 3; i++) {
      builder.add(bytes('hls_seg$i.m4s'));
    }
    await file.writeAsBytes(builder.takeBytes());

    final r = await measure(file.path);
    expect(r.lufs, isNotNull, reason: r.message);
    expect(r.lufs!.isFinite, isTrue);
  });

  testWidgets('reports a broken file', (t) async {
    final r = await measure(fixture('broken.mp3'));
    expect(r.lufs, isNull);
    expect(r.cancelled, isFalse);
    expect(r.message, isNotEmpty);
  });

  testWidgets('a cancelled job measures nothing', (t) async {
    final job = newLoudnessJob();
    cancelLoudness(job: job);
    final r = await measureLoudness(path: fixture('tagged.mp3'), job: job);
    expect(r.cancelled, isTrue);
    expect(r.lufs, isNull);
  });

  testWidgets('the measurer fills track_loudness with the real core', (
    t,
  ) async {
    final dir = await Directory.systemTemp.createTemp('owntune-measurer');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LibraryStorage(Directory('${dir.path}/library'));
    await storage.ensure();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    Future<int> add(String fixtureName, String fileName) async {
      await File(fixture(fixtureName)).copy(storage.audioFile(fileName).path);
      return db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              fileName: fileName,
              originalName: fixtureName,
              contentHash: fileName,
              durationMs: 1000,
              addedAt: DateTime(2026, 11, 26),
              title: Value(fixtureName),
            ),
          );
    }

    final good = await add('tagged.mp3', 'good.mp3');
    final broken = await add('broken.mp3', 'broken.mp3');
    final repo = LoudnessRepository(db);
    final measurer = LoudnessMeasurer(
      repo: repo,
      storage: storage,
      meter: RustLoudnessMeter(),
    );
    addTearDown(measurer.dispose);

    measurer.kick();
    await measurer.idle;

    expect(await repo.lufsOf(good), isNotNull);
    final rows = await db.select(db.trackLoudness).get();
    final failed = rows.singleWhere((r) => r.trackId == broken);
    expect(failed.lufs, isNull);
    expect(failed.failedVersion, kLoudnessMeasurerVersion);
  });
}
