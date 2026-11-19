import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/player/system_controls.dart';

import '../support/fakes.dart';

final _abc = [
  track(1, title: 'A song', artist: 'Juno Vale', durationMs: 200000),
  track(2, title: 'B song', artist: 'Juno Vale', durationMs: 200000),
  track(3, title: 'C song', artist: 'Juno Vale', durationMs: 200000),
];

Future<void> _play(WidgetTester t, String title) async {
  await t.tap(find.text(title));
  await t.pumpAndSettle();
}

void main() {
  late FakeSystemControls controls;
  late FakeAudioEngine engine;

  setUp(() {
    controls = FakeSystemControls();
    engine = FakeAudioEngine();
  });

  Future<void> pump(WidgetTester t, {Stream<List<Track>>? songsStream}) =>
      pumpApp(
        t,
        songs: _abc,
        songsStream: songsStream,
        engine: engine,
        overrides: [systemControlsProvider.overrideWithValue(controls)],
      );

  testWidgets('shows the playing song', (t) async {
    await pump(t);
    await _play(t, 'B song');

    final now = controls.shown.last!;
    expect(now.track.id, 2);
    expect(now.playing, isTrue);
    expect(now.hasNext, isTrue);
  });

  testWidgets('system play, pause, next and previous reach the player', (
    t,
  ) async {
    await pump(t);
    await _play(t, 'B song');
    final commands = controls.commands!;

    await commands.pause();
    await t.pumpAndSettle();
    expect(engine.playing, isFalse);
    expect(controls.shown.last!.playing, isFalse);

    await commands.play();
    await t.pumpAndSettle();
    expect(engine.playing, isTrue);

    await commands.next();
    await t.pumpAndSettle();
    expect(engine.current, 'hash3.mp3');
    expect(controls.shown.last!.track.id, 3);

    await commands.previous();
    await t.pumpAndSettle();
    expect(engine.current, 'hash2.mp3');
  });

  testWidgets('next is not offered on the last song with repeat off', (
    t,
  ) async {
    await pump(t);
    await _play(t, 'C song');
    expect(controls.shown.last!.hasNext, isFalse);
  });

  testWidgets('a seek from the system is published again', (t) async {
    await pump(t);
    await _play(t, 'A song');
    final before = controls.shown.length;

    await controls.commands!.seek(const Duration(seconds: 90));
    engine.emitPosition(const Duration(seconds: 90));
    await t.pumpAndSettle();

    expect(controls.shown.length, greaterThan(before));
    expect(controls.shown.last!.position.inMilliseconds, closeTo(90000, 1000));
  });

  testWidgets('steady playback is not republished every tick', (t) async {
    await pump(t);
    await _play(t, 'A song');
    final before = controls.shown.length;

    engine.emitPosition(const Duration(milliseconds: 200));
    engine.emitPosition(const Duration(milliseconds: 400));
    await t.pumpAndSettle();

    expect(controls.shown.length, before);
  });

  testWidgets('nothing is shown once the queue empties', (t) async {
    final library = StreamController<List<Track>>();
    addTearDown(library.close);
    await pump(t, songsStream: library.stream);
    library.add(_abc);
    await t.pumpAndSettle();
    await _play(t, 'A song');
    expect(controls.shown.last, isNotNull);

    library.add([]);
    await t.pumpAndSettle();
    expect(controls.shown.last, isNull);
  });
}
