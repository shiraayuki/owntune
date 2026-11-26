import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show AppLifecycleState;
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/loudness/loudness_measurer.dart';
import 'package:owntune/src/rust/api/loudness.dart' show LoudnessResult;

import '../support/fakes.dart';

const _measured = LoudnessResult(lufs: -9, cancelled: false);
const _failed = LoudnessResult(cancelled: false, message: 'cannot decode');
const _cancelled = LoudnessResult(cancelled: true);

void main() {
  final storage = LibraryStorage(Directory('/lib'));
  late FakeLoudnessRepository repo;
  late FakeLoudnessMeter meter;
  late LoudnessMeasurer measurer;

  LoudnessMeasurer make({bool foreground = true}) => LoudnessMeasurer(
    repo: repo,
    storage: storage,
    meter: meter,
    foreground: foreground,
  );

  String path(int id) => storage.audioFile('hash$id.mp3').path;

  /// Lets the measurer's awaits run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    repo = FakeLoudnessRepository(pending: [track(2), track(1)]);
    meter = FakeLoudnessMeter();
    measurer = make();
  });

  tearDown(() => measurer.dispose());

  test('measures pending tracks newest first, one at a time', () async {
    measurer.kick();
    await settle();
    expect(meter.measured, [path(2)]);

    meter.calls.single.complete(_measured);
    await settle();
    expect(repo.measured, [(2, -9.0)]);
    expect(meter.measured, [path(2), path(1)]);

    meter.calls.last.complete(_measured);
    await measurer.idle;
    expect(repo.measured, [(2, -9.0), (1, -9.0)]);
    expect(meter.measured, hasLength(2));
  });

  test('stores a failure with the measurer version', () async {
    meter.instant = _failed;
    measurer.kick();
    await measurer.idle;

    expect(repo.failed, [(2, kLoudnessMeasurerVersion), (1, 1)]);
    expect(repo.measured, isEmpty);
  });

  test('stores a failure when measure throws', () async {
    measurer.kick();
    await settle();
    meter.calls.single.completeError(StateError('bridge died'));
    await settle();

    expect(repo.failed.first, (2, kLoudnessMeasurerVersion));
  });

  test('going to the background cancels and stores nothing', () async {
    measurer.kick();
    await settle();
    final job = meter.jobs.single;

    measurer.setForeground(false);
    expect(meter.cancelled, [job]);
    meter.calls.single.complete(_cancelled);
    await measurer.idle;
    expect(repo.measured, isEmpty);
    expect(repo.failed, isEmpty);
    expect(meter.measured, [path(2)]);

    measurer.setForeground(true);
    await settle();
    expect(meter.measured, [path(2), path(2)]);
    expect(meter.jobs.last, isNot(job));
  });

  test('does not start while in the background', () async {
    measurer.dispose();
    measurer = make(foreground: false);
    measurer.kick();
    await settle();
    await measurer.idle;

    expect(meter.measured, isEmpty);
  });

  test('a kick while measuring picks up tracks added meanwhile', () async {
    repo = FakeLoudnessRepository(pending: [track(1)]);
    measurer.dispose();
    measurer = make();
    measurer.kick();
    await settle();

    repo.pending.insert(0, track(3));
    measurer.kick();
    meter.calls.single.complete(_measured);
    await settle();

    expect(meter.measured, [path(1), path(3)]);
  });

  test('a repository error ends the loop quietly', () async {
    repo.throwOnNext = true;
    measurer.kick();
    await measurer.idle;
    expect(meter.measured, isEmpty);

    measurer.kick();
    await settle();
    expect(meter.measured, [path(2)]);
  });

  test('dispose cancels the running job', () async {
    measurer.kick();
    await settle();

    measurer.dispose();
    expect(meter.cancelled, [meter.jobs.single]);
  });

  testWidgets('the app measures pending songs and stops in the background', (
    t,
  ) async {
    final pending = FakeLoudnessRepository(pending: [track(7)]);
    final appMeter = FakeLoudnessMeter();
    await pumpApp(
      t,
      songs: [track(7)],
      storage: storage,
      loudness: pending,
      meter: appMeter,
    );

    expect(appMeter.measured, [path(7)]);

    void go(List<AppLifecycleState> states) {
      for (final state in states) {
        t.binding.handleAppLifecycleStateChanged(state);
      }
    }

    go(const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    expect(appMeter.cancelled, [appMeter.jobs.single]);
    go(const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
  });
}
