import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/sidestore_source.dart';

void main() {
  final source = buildSidestoreSource(
    repo: 'shiraayuki/owntune',
    tag: 'v0.2.0',
    buildNumber: '17',
    date: DateTime.utc(2026, 11, 18),
    ipaSize: 7654321,
  );
  final app = (source['apps'] as List).single as Map<String, dynamic>;
  final version = (app['versions'] as List).single as Map<String, dynamic>;

  test('source points to the latest release', () {
    expect(source['identifier'], 'dev.owntune.source');
    expect(
      source['sourceURL'],
      'https://github.com/shiraayuki/owntune/releases/latest/download/source.json',
    );
  });

  test('app matches the bundle ID and names no person', () {
    expect(app['bundleIdentifier'], 'dev.owntune.app');
    expect(app['developerName'], 'owntune');
    expect(
      app['iconURL'],
      'https://raw.githubusercontent.com/shiraayuki/owntune/main/'
      '$sidestoreIconPath',
    );
  });

  test('the icon file exists in the repo', () {
    expect(File(sidestoreIconPath).existsSync(), isTrue);
  });

  test('version without v prefix, download link to exactly this release', () {
    expect(version['version'], '0.2.0');
    expect(version['buildVersion'], '17');
    expect(version['date'], '2026-11-18');
    expect(version['size'], 7654321);
    expect(version['minOSVersion'], '15.0');
    expect(
      version['downloadURL'],
      'https://github.com/shiraayuki/owntune/releases/download/v0.2.0/owntune.ipa',
    );
  });

  test('rejects tags not in vX.Y.Z format', () {
    expect(
      () => buildSidestoreSource(
        repo: 'a/b',
        tag: 'main',
        buildNumber: '1',
        date: DateTime.utc(2026),
        ipaSize: 1,
      ),
      throwsArgumentError,
    );
  });
}
