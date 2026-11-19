import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/player/audio_engine.dart';
import 'package:owntune/player/audio_setup.dart';

import 'support/fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory fixtures;
  late JustAudioEngine engine;

  setUpAll(() async {
    await initAudio();
    fixtures = fixturesDir();
  });

  setUp(() => engine = JustAudioEngine());
  tearDown(() => engine.dispose());

  testWidgets('plays a fixture to its end', (t) async {
    final positions = <Duration>[];
    final sub = engine.position.listen(positions.add);
    addTearDown(sub.cancel);
    final done = engine.completed.first;

    await engine.load(File('${fixtures.path}/tagged.mp3'));
    await engine.play();

    await t.runAsync(() => done.timeout(const Duration(seconds: 10)));
    expect(positions.any((p) => p > Duration.zero), isTrue);
  });

  testWidgets('load throws for a non-audio file', (t) async {
    // runAsync reports thrown errors to the test itself, so catch inside.
    final error = await t.runAsync(() async {
      try {
        await engine
            .load(File('${fixtures.path}/broken.mp3'))
            .timeout(const Duration(seconds: 10));
        return null;
      } on Object catch (e) {
        return e;
      }
    });
    expect(error, isNotNull);
    // media_kit reports the failure as an event only; a hang would time out.
    expect(error, isNot(isA<TimeoutException>()));
  });
}
