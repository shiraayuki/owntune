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

  test('Quelle zeigt auf das neueste Release', () {
    expect(source['identifier'], 'dev.owntune.source');
    expect(
      source['sourceURL'],
      'https://github.com/shiraayuki/owntune/releases/latest/download/source.json',
    );
  });

  test('App passt zur Bundle-ID und nennt keinen Personennamen', () {
    expect(app['bundleIdentifier'], 'dev.owntune.app');
    expect(app['developerName'], 'owntune');
    expect(
      app['iconURL'],
      startsWith('https://raw.githubusercontent.com/shiraayuki/owntune/'),
    );
  });

  test('Version ohne v-Präfix, mit Download-Link auf genau dieses Release', () {
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

  test('lehnt Tags ohne vX.Y.Z-Format ab', () {
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
