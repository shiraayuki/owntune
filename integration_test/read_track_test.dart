import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/src/rust/api/library.dart';
import 'package:owntune/src/rust/frb_generated.dart';

/// Absolute path of an audio fixture. The test process runs in the project
/// root on Linux desktop; fail loudly if the fixture is not where we expect.
String fixture(String name) {
  final file = File('${Directory.current.path}/test/fixtures/audio/$name');
  expect(file.existsSync(), isTrue, reason: 'missing fixture ${file.path}');
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('readTrack reads the tags of an MP3', (t) async {
    final r = await readTrack(path: fixture('tagged.mp3'));
    expect(r.status, ReadStatus.ok);
    expect(r.track!.title, 'After the Rain');
    expect(r.track!.cover!.fileExtension, 'png');
  });

  testWidgets('readTrack reports OGG as unsupported', (t) async {
    final r = await readTrack(path: fixture('evening-walk.ogg'));
    expect(r.status, ReadStatus.unsupported);
    expect(r.track, isNull);
  });
}
