import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fixture_data.dart';

Directory? _materialized;

/// The audio fixtures folder as the test process sees it.
///
/// On the desktop the tests run in the project root and read
/// `test/fixtures/audio` directly. On a phone (Android emulator, iPhone) the
/// host file system is not reachable and `flutter test` reinstalls the app,
/// so the fixtures are embedded (`tool/embed_fixtures.dart`) and written to a
/// temporary folder on the device once per test file.
Directory fixturesDir() {
  if (Platform.isAndroid || Platform.isIOS) {
    return _materialized ??= _writeEmbedded();
  }
  final dir = Directory('${Directory.current.path}/test/fixtures/audio');
  expect(dir.existsSync(), isTrue, reason: 'missing fixtures ${dir.path}');
  return dir;
}

Directory _writeEmbedded() {
  final dir = Directory.systemTemp.createTempSync('owntune_fixtures');
  for (final MapEntry(:key, :value) in fixtureData.entries) {
    File('${dir.path}/$key').writeAsBytesSync(base64Decode(value));
  }
  return dir;
}
