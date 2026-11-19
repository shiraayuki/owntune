import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/player/play_queue.dart';
import 'package:owntune/player/player_snapshot.dart';

void main() {
  test('toJson and tryParse round-trip', () {
    const s = PlayerSnapshot(
      trackIds: [3, 1, 3],
      index: 2,
      source: 'Paper Lanterns',
      repeat: QueueRepeat.one,
      position: Duration(milliseconds: 84250),
    );
    final back = PlayerSnapshot.tryParse(s.toJson())!;
    expect(back.trackIds, [3, 1, 3]);
    expect(back.index, 2);
    expect(back.source, 'Paper Lanterns');
    expect(back.repeat, QueueRepeat.one);
    expect(back.position, const Duration(milliseconds: 84250));
  });

  test('a snapshot without source round-trips', () {
    const s = PlayerSnapshot(trackIds: [1], index: 0);
    final back = PlayerSnapshot.tryParse(s.toJson())!;
    expect(back.source, isNull);
    expect(back.repeat, QueueRepeat.off);
    expect(back.position, Duration.zero);
  });

  test('tryParse rejects malformed JSON, wrong types and a bad index', () {
    for (final bad in [
      null,
      '',
      'not json',
      '[]',
      '{"trackIds": "1", "index": 0}',
      '{"trackIds": [1, "x"], "index": 0}',
      '{"trackIds": [1, 2], "index": 2}',
      '{"trackIds": [1, 2], "index": -1}',
      '{"trackIds": [], "index": 0}',
      '{"trackIds": [1], "index": 0, "positionMs": "5"}',
    ]) {
      expect(PlayerSnapshot.tryParse(bad), isNull, reason: '$bad');
    }
  });

  test('an unknown repeat mode falls back to off', () {
    final s = PlayerSnapshot.tryParse(
      '{"trackIds": [1], "index": 0, "repeat": "sometimes"}',
    )!;
    expect(s.repeat, QueueRepeat.off);
  });

  test('round-trips shuffleOrder', () {
    const s = PlayerSnapshot(
      trackIds: [3, 1, 2],
      index: 0,
      shuffleOrder: [1, 2, 0],
    );
    expect(PlayerSnapshot.tryParse(s.toJson())!.shuffleOrder, [1, 2, 0]);
    expect(
      PlayerSnapshot.tryParse(
        const PlayerSnapshot(trackIds: [1], index: 0).toJson(),
      )!.shuffleOrder,
      isNull,
    );
  });

  test('a v0.4.1 snapshot has no shuffleOrder', () {
    final back = PlayerSnapshot.tryParse(
      '{"trackIds":[1,2],"index":1,"repeat":"all","positionMs":5000}',
    )!;
    expect(back.trackIds, [1, 2]);
    expect(back.shuffleOrder, isNull);
  });

  test('a broken shuffleOrder is dropped', () {
    for (final order in ['[0,0]', '[5,0]', '[0]', '"x"', '[0,"1"]']) {
      final back = PlayerSnapshot.tryParse(
        '{"trackIds":[1,2],"index":1,"shuffleOrder":$order}',
      );
      expect(back, isNotNull, reason: order);
      expect(back!.trackIds, [1, 2], reason: order);
      expect(back.shuffleOrder, isNull, reason: order);
    }
  });
}
