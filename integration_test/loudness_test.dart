import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/download/mp4_duration.dart';
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
}
