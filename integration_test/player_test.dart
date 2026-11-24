import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/player/audio_engine.dart';
import 'package:owntune/player/audio_setup.dart';
import 'package:owntune/player/system_controls.dart';

import '../test/support/fakes.dart' show track;

import 'support/fixtures.dart';

void main() {
  // A hang (seen intermittently in CI) fails the test instead of the job.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().defaultTestTimeout =
      const Timeout(Duration(minutes: 1));

  late Directory fixtures;
  late JustAudioEngine engine;

  setUpAll(() async {
    await initAudio();
    fixtures = fixturesDir();
  });

  setUp(() => engine = JustAudioEngine());
  tearDown(() => engine.dispose().timeout(const Duration(seconds: 15)));

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

  testWidgets('a load cut off by the next one does not fail the next', (
    t,
  ) async {
    final errors = <Object>[];
    final sub = engine.errors.listen(errors.add);
    addTearDown(sub.cancel);

    await t.runAsync(() async {
      final first = engine
          .load(File('${fixtures.path}/tagged.flac'))
          .then<Object?>((_) => null, onError: (Object e) => e);
      await engine
          .load(File('${fixtures.path}/tagged.mp3'))
          .timeout(const Duration(seconds: 10));
      await first;
      final done = engine.completed.first;
      await engine.play();
      await done.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect(errors, isEmpty);
  });

  testWidgets('a failed load does not fail the following one', (t) async {
    final errors = <Object>[];
    final sub = engine.errors.listen(errors.add);
    addTearDown(sub.cancel);

    final error = await t.runAsync(() async {
      Object? failed;
      try {
        await engine
            .load(File('${fixtures.path}/broken.mp3'))
            .timeout(const Duration(seconds: 10));
      } on Object catch (e) {
        failed = e;
      }
      await engine
          .load(File('${fixtures.path}/tagged.mp3'))
          .timeout(const Duration(seconds: 10));
      final done = engine.completed.first;
      await engine.play();
      await done.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return failed;
    });
    expect(error, isNotNull);
    expect(errors, isEmpty);
  });

  testWidgets('the system controls take a song', (t) async {
    final controls = await AudioServiceControls.init();
    final commands = _RecordingCommands();
    controls
      ..connect(commands)
      ..show(
        NowPlaying(
          track: track(1, title: 'After the Rain', durationMs: 1000),
          playing: true,
          position: Duration.zero,
          hasNext: true,
        ),
      )
      ..show(null);
  }, skip: !(Platform.isAndroid || Platform.isIOS));
}

class _RecordingCommands implements SystemCommands {
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> seek(Duration position) async {}
}
