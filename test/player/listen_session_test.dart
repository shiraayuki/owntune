import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/player/listen_session.dart';
import 'package:owntune/player/queue_source.dart';

ListenSession session({int durationMs = 240000}) => ListenSession(
  trackId: 1,
  durationMs: durationMs,
  sourceKind: QueueSourceKind.songs,
);

void main() {
  final t0 = DateTime(2026, 11, 24, 12);

  test('steps add up while moving forward', () {
    final s = session();
    for (var i = 0; i <= 10; i++) {
      s.advance(Duration(seconds: i), t0.add(Duration(seconds: i)));
    }
    expect(s.listenedMs, 10000);
    // The first step that adds time is the one to 1 s.
    expect(s.startedAt, t0.add(const Duration(seconds: 1)));
  });

  test('the first advance only sets the baseline', () {
    final s = session();
    expect(s.advance(const Duration(seconds: 50), t0), isFalse);
    expect(s.listenedMs, 0);
    expect(s.startedAt, isNull);
  });

  test('a seek resets the baseline', () {
    final s = session();
    for (var i = 0; i <= 10; i++) {
      s.advance(Duration(seconds: i), t0);
    }
    s.resetBaseline(const Duration(seconds: 100));
    s.advance(const Duration(seconds: 101), t0);
    expect(s.listenedMs, 11000);
  });

  test('steps over 3 s and backward steps are ignored', () {
    final s = session();
    s.advance(Duration.zero, t0);
    s.advance(const Duration(seconds: 1), t0);
    expect(s.listenedMs, 1000);
    // A jump of 10 s adds nothing but moves the baseline.
    s.advance(const Duration(seconds: 11), t0);
    expect(s.listenedMs, 1000);
    s.advance(const Duration(seconds: 12), t0);
    expect(s.listenedMs, 2000);
    // A step of exactly 3 s counts.
    s.advance(const Duration(seconds: 15), t0);
    expect(s.listenedMs, 5000);
    // Backward and zero steps add nothing; counting continues from there.
    s.advance(const Duration(seconds: 5), t0);
    s.advance(const Duration(seconds: 5), t0);
    expect(s.listenedMs, 5000);
    s.advance(const Duration(seconds: 6), t0);
    expect(s.listenedMs, 6000);
  });

  test('counts once at 30 s', () {
    final s = session();
    final results = <bool>[];
    for (var i = 0; i <= 40; i++) {
      results.add(s.advance(Duration(seconds: i), t0));
    }
    // Index i is the step to i seconds: the 30th step crosses 30000 ms.
    expect(results.where((r) => r), hasLength(1));
    expect(results[30], isTrue);
    expect(results[29], isFalse);
    expect(s.counted, isTrue);
    expect(s.listenedMs, 40000);
  });

  test('a short song counts on complete', () {
    final s = session(durationMs: 20000);
    s.advance(Duration.zero, t0);
    for (var i = 1; i <= 5; i++) {
      s.advance(Duration(seconds: i), t0);
    }
    expect(s.counted, isFalse);
    expect(s.complete(), isTrue);
    expect(s.counted, isTrue);

    final long = session(durationMs: 240000);
    long.advance(Duration.zero, t0);
    long.advance(const Duration(seconds: 1), t0);
    expect(long.complete(), isFalse);
    expect(long.counted, isFalse);
  });

  test('a short song with nothing heard does not count on complete', () {
    final s = session(durationMs: 20000);
    expect(s.complete(), isFalse);
    expect(s.counted, isFalse);
    // Less than 1 s heard is still nothing.
    s.advance(Duration.zero, t0);
    s.advance(const Duration(milliseconds: 900), t0);
    expect(s.complete(), isFalse);
  });

  test('a song just over 30 s that plays fully counts on complete', () {
    final s = session(durationMs: 31000);
    s.advance(Duration.zero, t0);
    // 29 500 ms heard (steps of 500 ms): just short of 30 s.
    for (var i = 1; i <= 59; i++) {
      s.advance(Duration(milliseconds: i * 500), t0);
    }
    expect(s.listenedMs, 29500);
    expect(s.counted, isFalse);
    expect(s.complete(), isTrue);
    expect(s.counted, isTrue);
  });

  test('a long song heard only partly does not count on complete', () {
    final s = session(durationMs: 31000);
    s.advance(Duration.zero, t0);
    for (var i = 1; i <= 20; i++) {
      s.advance(Duration(seconds: i), t0);
    }
    expect(s.complete(), isFalse);
  });

  test('complete after advance counted it returns false', () {
    final s = session(durationMs: 29000);
    for (var i = 0; i <= 5; i++) {
      s.advance(Duration(seconds: i), t0);
    }
    expect(s.complete(), isTrue);
    expect(s.complete(), isFalse);
    // Never counted again by advance either.
    expect(s.advance(const Duration(seconds: 6), t0), isFalse);
  });

  test('advance does not return true again after complete counted it', () {
    final s = session(durationMs: 20000);
    s.advance(Duration.zero, t0);
    s.advance(const Duration(seconds: 2), t0);
    expect(s.complete(), isTrue);
    for (var i = 0; i <= 40; i++) {
      expect(s.advance(Duration(seconds: i), t0), isFalse);
    }
    expect(s.counted, isTrue);
  });

  test('resetBaseline then advance continues from the given position', () {
    final s = session();
    s.resetBaseline(const Duration(seconds: 20));
    s.advance(const Duration(seconds: 21), t0);
    expect(s.listenedMs, 1000);
    expect(s.startedAt, t0);
  });

  test('rowId is settable', () {
    final s = session();
    expect(s.rowId, isNull);
    s.rowId = 7;
    expect(s.rowId, 7);
  });
}
