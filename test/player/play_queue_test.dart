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
    final all = last.withRepeat(QueueRepeat.all);
    expect(all.nextIndex(auto: false), 0);
    expect(all.hasNext, isTrue);
    expect(last.withRepeat(QueueRepeat.one).hasNext, isFalse);
  });

  test('repeat one repeats only when the song ends', () {
    final q = PlayQueue.of([1, 2, 3], start: 0).withRepeat(QueueRepeat.one);
    expect(q.nextIndex(auto: true), 0);
    expect(q.nextIndex(auto: false), 1);
  });

  test('QueueRepeat cycles off, all, one', () {
    expect(QueueRepeat.off.next, QueueRepeat.all);
    expect(QueueRepeat.all.next, QueueRepeat.one);
    expect(QueueRepeat.one.next, QueueRepeat.off);
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

  test('moveUpcoming takes the index after removal', () {
    final q = PlayQueue.of([1, 2, 3, 4], start: 0).moveUpcoming(2, 0);
    expect(ids(q), [1, 4, 2, 3]);
  });

  test('moveUpcoming reorders only upcoming entries', () {
    final q = PlayQueue.of([1, 2, 3, 4], start: 0).moveUpcoming(0, 2);
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

  group('shuffle', () {
    List<QueueEntry> reverse(List<QueueEntry> es) => es.reversed.toList();
    List<int>? originalIds(PlayQueue q) =>
        q.original == null ? null : [for (final e in q.original!) e.trackId];
    PlayQueue shuffledAt2() =>
        PlayQueue.of([1, 2, 3, 4], start: 1).shuffleOn(reverse);

    test('shuffle on keeps the current song first', () {
      final q = shuffledAt2();
      expect(ids(q), [2, 4, 3, 1]);
      expect(q.index, 0);
      expect(q.shuffled, isTrue);
      expect(originalIds(q), [1, 2, 3, 4]);
    });

    test('shuffle on without keepCurrent spreads all', () {
      final q = PlayQueue.of([
        1,
        2,
        3,
        4,
      ], start: 1).shuffleOn(reverse, keepCurrent: false);
      expect(ids(q), [4, 3, 2, 1]);
      expect(q.index, 0);
    });

    test('shuffle off continues in the original order', () {
      final q = shuffledAt2().withIndex(2).shuffleOff();
      expect(ids(q), [1, 2, 3, 4]);
      expect(q.index, 2);
      expect(q.current!.trackId, 3);
      expect(q.shuffled, isFalse);
      expect(q.original, isNull);
    });

    test('Play Next while shuffled stays after the current song in both '
        'orders', () {
      final q = shuffledAt2().insertNext(9);
      expect(ids(q), [2, 9, 4, 3, 1]);
      final off = q.shuffleOff();
      expect(ids(off), [1, 2, 9, 3, 4]);
      expect(off.index, 1);
    });

    test('Play Later lands at the end of both orders', () {
      final q = shuffledAt2().append(9);
      expect(ids(q), [2, 4, 3, 1, 9]);
      expect(ids(q.shuffleOff()), [1, 2, 3, 4, 9]);
    });

    test('a removed song stays gone after shuffle off', () {
      final q = shuffledAt2();
      final four = q.entries.firstWhere((e) => e.trackId == 4).key;
      expect(ids(q.remove(four).shuffleOff()), [1, 2, 3]);
    });

    test('reordering Up Next changes only the shuffled order', () {
      final q = shuffledAt2().moveUpcoming(0, 2);
      expect(ids(q), [2, 3, 1, 4]);
      expect(ids(q.shuffleOff()), [1, 2, 3, 4]);
    });

    test('clear Up Next while shuffled', () {
      final off = shuffledAt2().clearUpcoming().shuffleOff();
      expect(ids(off), [2]);
      expect(off.index, 0);
    });

    test('retain drops deleted songs from both orders', () {
      final (:queue, :currentRemoved) = shuffledAt2().retain({1, 2, 3});
      expect(currentRemoved, isFalse);
      expect(ids(queue), [2, 3, 1]);
      expect(originalIds(queue), [1, 2, 3]);
    });

    test('the same track twice survives shuffle on and off', () {
      final q = PlayQueue.of([1, 1, 2], start: 0);
      final round = q.shuffleOn(reverse).shuffleOff();
      expect(ids(round), [1, 1, 2]);
      expect(
        [for (final e in round.entries) e.key],
        [for (final e in q.entries) e.key],
      );
    });

    test('following wraps with a new order under repeat all', () {
      final q = shuffledAt2().withRepeat(QueueRepeat.all).withIndex(3);
      final ended = q.current!;
      final next = q.following(auto: true, spread: reverse)!;
      expect(next.index, 0);
      expect(next.current, isNot(ended));
      expect(next.entries.length, 4);
      expect(next.shuffled, isTrue);
      expect(originalIds(next), [1, 2, 3, 4]);
    });

    test('following stops at the end with repeat off', () {
      final q = shuffledAt2().withIndex(3);
      expect(q.following(auto: true, spread: reverse), isNull);
    });

    test('following repeats one', () {
      final q = shuffledAt2().withRepeat(QueueRepeat.one).withIndex(1);
      expect(q.following(auto: true, spread: reverse)!.index, 1);
      expect(q.following(auto: false, spread: reverse)!.index, 2);
    });

    test('following without shuffle wraps in the same order', () {
      final q = PlayQueue.of([1, 2, 3], start: 2).withRepeat(QueueRepeat.all);
      final next = q.following(auto: false, spread: reverse)!;
      expect(ids(next), [1, 2, 3]);
      expect(next.index, 0);
    });

    test('of with originalOrder restores the unshuffled order', () {
      final q = PlayQueue.of([3, 1, 2], start: 0, originalOrder: [1, 2, 0]);
      expect(q.shuffled, isTrue);
      expect(originalIds(q), [1, 2, 3]);
    });

    test('an empty shuffled queue stays shuffled', () {
      final (:queue, currentRemoved: _) = shuffledAt2().retain(const {});
      expect(queue.isEmpty, isTrue);
      expect(queue.shuffled, isTrue);
      expect(const PlayQueue(original: []).shuffled, isTrue);
    });
  });
}
