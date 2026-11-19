import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/fixture_data.dart';
import '../../tool/embed_fixtures.dart';

void main() {
  test('embedded fixtures match test/fixtures/audio', () {
    final onDisk = audioFixtures(Directory('test/fixtures/audio'));
    expect(onDisk.keys, containsAll(['tagged.mp3', 'broken.mp3', 'demo_3.wav']));
    expect(
      fixtureData.keys.toSet(),
      onDisk.keys.toSet(),
      reason: 'run: dart run tool/embed_fixtures.dart',
    );
    for (final MapEntry(:key, :value) in onDisk.entries) {
      expect(
        base64Decode(fixtureData[key]!),
        value,
        reason: '$key is stale; run: dart run tool/embed_fixtures.dart',
      );
    }
  });

  test('the README is not a fixture', () {
    expect(
      audioFixtures(Directory('test/fixtures/audio')).keys,
      isNot(contains('README.md')),
    );
  });
}
