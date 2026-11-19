import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/player/play_queue.dart';

List<int> ids(PlayQueue q) => [for (final e in q.entries) e.trackId];

void main() {
  test('of starts at the tapped song', () {
    final q = PlayQueue.of([1, 2, 3], start: 1, source: 'Songs');
    expect(q.current!.trackId, 2);
    expect([for (final e in q.upcoming) e.trackId], [3]);
    expect(q.source, 'Songs');
  });

  test('nextIndex wraps only with repeat all', () {
    final last = PlayQueue.of([1, 2, 3], start: 2);
    expect(last.nextIndex(auto: false), isNull);
    expect(last.hasNext, isFalse);
    final all = last.withRepeat(RepeatMode.all);
    expect(all.nextIndex(auto: false), 0);
    expect(all.hasNext, isTrue);
    expect(last.withRepeat(RepeatMode.one).hasNext, isFalse);
  });

  test('repeat one repeats only when the song ends', () {
    final q = PlayQueue.of([1, 2, 3], start: 0).withRepeat(RepeatMode.one);
    expect(q.nextIndex(auto: true), 0);
    expect(q.nextIndex(auto: false), 1);
  });

  test('RepeatMode cycles off, all, one', () {
    expect(RepeatMode.off.next, RepeatMode.all);
    expect(RepeatMode.all.next, RepeatMode.one);
    expect(RepeatMode.one.next, RepeatMode.off);
  });

  test('previousIndex is null on the first entry', () {
    expect(PlayQueue.of([1, 2], start: 0).previousIndex, isNull);
    expect(PlayQueue.of([1, 2], start: 1).previousIndex, 0);
  });

  test('insertNext puts the song right after the current one', () {
    final q = PlayQueue.of([1, 2, 3], start: 0).insertNext(9);
    expect(ids(q), [1, 9, 2, 3]);
    expect(q.index, 0);
  });

  test('append adds it at the end', () {
    expect(ids(PlayQueue.of([1, 2], start: 0).append(9)), [1, 2, 9]);
  });

  test('insertNext and append on an empty queue give a one-song queue', () {
    for (final q in [
      PlayQueue.empty.insertNext(5),
      PlayQueue.empty.append(5),
    ]) {
      expect(ids(q), [5]);
      expect(q.index, 0);
      expect(q.current!.trackId, 5);
    }
  });

  test('duplicates get distinct keys', () {
    final q = PlayQueue.of([1, 2], start: 0).append(2);
    expect(ids(q), [1, 2, 2]);
    expect(q.entries[1].key, isNot(q.entries[2].key));
    expect({for (final e in q.entries) e.key}.length, 3);
  });

  test('moveUpcoming reorders only upcoming entries', () {
    final q = PlayQueue.of([1, 2, 3, 4], start: 0).moveUpcoming(0, 3);
    expect(ids(q), [1, 3, 4, 2]);
    expect(q.index, 0);
  });

  test('remove and clearUpcoming keep the current song', () {
    final q = PlayQueue.of([1, 2, 3, 4], start: 1);
    final cleared = q.clearUpcoming();
    expect(ids(cleared), [1, 2]);
    expect(cleared.index, 1);
    final removed = q.remove(q.entries[3].key);
    expect(ids(removed), [1, 2, 3]);
    expect(removed.current!.trackId, 2);
    final before = q.remove(q.entries[0].key);
    expect(ids(before), [2, 3, 4]);
    expect(before.current!.trackId, 2);
  });

  test('jumpTo makes the entry current', () {
    final q = PlayQueue.of([1, 2, 3], start: 0);
    expect(q.jumpTo(q.entries[2].key).index, 2);
  });

  test('retain keeps the current song when others go', () {
    final r = PlayQueue.of([1, 2, 3], start: 1).retain({1, 2});
    expect(ids(r.queue), [1, 2]);
    expect(r.queue.index, 1);
    expect(r.currentRemoved, isFalse);
  });

  test('retain moves to the following song when the current one goes', () {
    final r = PlayQueue.of([1, 2, 3], start: 1).retain({1, 3});
    expect(r.queue.current!.trackId, 3);
    expect(r.currentRemoved, isTrue);
  });

  test('retain falls back to the last remaining song when none follows', () {
    final r = PlayQueue.of([1, 2, 3], start: 2).retain({1, 2});
    expect(r.queue.current!.trackId, 2);
    expect(r.currentRemoved, isTrue);
  });

  test('retain of nothing empties the queue', () {
    final r = PlayQueue.of([1, 2, 3], start: 1).retain({});
    expect(r.queue.isEmpty, isTrue);
    expect(r.queue.current, isNull);
    expect(r.currentRemoved, isTrue);
  });

  test('remove by key after a retain hits the right entry', () {
    final q = PlayQueue.of([1, 2, 3, 4], start: 0);
    final key = q.entries[3].key;
    final r = q.retain({1, 2, 4}).queue.remove(key);
    expect(ids(r), [1, 2]);
  });

  test('keys stay unique after removals', () {
    final q = PlayQueue.of([1, 2, 3], start: 0);
    final r = q.remove(q.entries[2].key).append(7);
    expect({for (final e in r.entries) e.key}.length, r.entries.length);
    expect(r.entries.last.key, isNot(q.entries[2].key));
  });
}
