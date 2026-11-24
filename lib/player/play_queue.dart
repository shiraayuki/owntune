import 'package:owntune/player/queue_source.dart';

/// Repeat mode of the player; the button cycles off → all → one.
enum QueueRepeat {
  off,
  all,
  one;

  QueueRepeat get next => switch (this) {
    off => all,
    all => one,
    one => off,
  };
}

/// One row of the queue. The same track may be queued more than once, so
/// rows are identified by [key], never by [trackId]. [queued] marks entries
/// added with Play Next / Play Later.
class QueueEntry {
  const QueueEntry(this.key, this.trackId, {this.queued = false});

  final int key;
  final int trackId;
  final bool queued;

  @override
  bool operator ==(Object other) =>
      other is QueueEntry &&
      other.key == key &&
      other.trackId == trackId &&
      other.queued == queued;

  @override
  int get hashCode => Object.hash(key, trackId, queued);
}

/// Orders entries for shuffle (the controller spreads them by artist and
/// album, see `spread`).
typedef Spread = List<QueueEntry> Function(List<QueueEntry> entries);

/// The play queue: entries, the current [index], where it was started
/// from ([source], e.g. an album) and the [repeat] mode.
///
/// While [shuffled], [entries] are the shuffled play order and [original]
/// keeps the unshuffled order, so everything that follows [entries] (Up
/// Next, Previous, the system controls) needs to know nothing of shuffle.
///
/// Immutable; every change returns a new queue. Entry keys are unique within
/// a queue and never reused.
class PlayQueue {
  const PlayQueue({
    this.entries = const [],
    this.index = 0,
    this.source,
    this.repeat = QueueRepeat.off,
    this.original,
    this._nextKey = 0,
  });

  static const empty = PlayQueue();

  /// [originalOrder] (from a saved state) makes the queue shuffled: the
  /// positions in [trackIds] that give the unshuffled order;
  /// [queuedPositions] are the positions of entries added with Play Next /
  /// Later.
  factory PlayQueue.of(
    List<int> trackIds, {
    required int start,
    QueueSource? source,
    QueueRepeat repeat = QueueRepeat.off,
    List<int>? originalOrder,
    Set<int> queuedPositions = const {},
  }) {
    final entries = [
      for (final (i, id) in trackIds.indexed)
        QueueEntry(i, id, queued: queuedPositions.contains(i)),
    ];
    return PlayQueue(
      entries: entries,
      index: start,
      source: source,
      repeat: repeat,
      original: originalOrder == null
          ? null
          : [for (final p in originalOrder) entries[p]],
      nextKey: trackIds.length,
    );
  }

  final List<QueueEntry> entries;
  final int index;
  final QueueSource? source;
  final QueueRepeat repeat;

  /// The unshuffled order while shuffled; null when shuffle is off.
  final List<QueueEntry>? original;
  final int _nextKey;

  bool get isEmpty => entries.isEmpty;

  bool get shuffled => original != null;

  QueueEntry? get current => isEmpty ? null : entries[index];

  /// The entries after the current one.
  List<QueueEntry> get upcoming =>
      isEmpty ? const [] : entries.sublist(index + 1);

  /// False only on the last entry with repeat off (or repeat one, where Next
  /// still has nowhere to go).
  bool get hasNext =>
      !isEmpty && (index + 1 < entries.length || repeat == QueueRepeat.all);

  /// The entry to play after the current one; [auto] is true when the song
  /// ended by itself (repeat one then repeats it). Null means stop.
  int? nextIndex({required bool auto}) {
    if (isEmpty) return null;
    if (auto && repeat == QueueRepeat.one) return index;
    if (index + 1 < entries.length) return index + 1;
    return repeat == QueueRepeat.all ? 0 : null;
  }

  /// Null on the first entry (the caller restarts the song).
  int? get previousIndex => index > 0 ? index - 1 : null;

  PlayQueue _copy({
    List<QueueEntry>? entries,
    int? index,
    QueueRepeat? repeat,
  }) => PlayQueue(
    entries: entries ?? this.entries,
    index: index ?? this.index,
    source: source,
    repeat: repeat ?? this.repeat,
    original: original,
    nextKey: _nextKey,
  );

  /// Like [_copy] for removals: [original] keeps only entries still queued.
  PlayQueue _without(List<QueueEntry> entries, int index) {
    final keys = {for (final e in entries) e.key};
    return PlayQueue(
      entries: entries,
      index: index,
      source: source,
      repeat: repeat,
      original: original?.where((e) => keys.contains(e.key)).toList(),
      nextKey: _nextKey,
    );
  }

  PlayQueue _withNew(
    List<QueueEntry> entries,
    int index, {
    List<QueueEntry>? original,
  }) => PlayQueue(
    entries: entries,
    index: index,
    source: source,
    repeat: repeat,
    original: original,
    nextKey: _nextKey + 1,
  );

  /// Turns shuffle on: with [keepCurrent] the current entry stays and comes
  /// first, followed by all others in [spread] order; otherwise all entries
  /// are spread. The unshuffled order is kept in [original].
  PlayQueue shuffleOn(Spread spread, {bool keepCurrent = true}) {
    final unshuffled = original ?? entries;
    final current = this.current;
    final order = keepCurrent && current != null
        ? [
            current,
            ...spread([...entries]..removeAt(index)),
          ]
        : spread(entries);
    return PlayQueue(
      entries: order,
      source: source,
      repeat: repeat,
      original: unshuffled,
      nextKey: _nextKey,
    );
  }

  /// Turns shuffle off and continues in the unshuffled order from the
  /// current entry.
  PlayQueue shuffleOff() {
    final unshuffled = original;
    if (unshuffled == null) return this;
    final key = current?.key;
    final i = unshuffled.indexWhere((e) => e.key == key);
    return PlayQueue(
      entries: unshuffled,
      index: i < 0 ? 0 : i,
      source: source,
      repeat: repeat,
      nextKey: _nextKey,
    );
  }

  /// The queue after the current entry; [auto] as for [nextIndex]. Null
  /// means stop. A shuffled queue wrapping around under repeat all is
  /// shuffled again, without the entry that just ended coming first.
  PlayQueue? following({required bool auto, required Spread spread}) {
    final next = nextIndex(auto: auto);
    if (next == null) return null;
    final wraps = next == 0 && index == entries.length - 1;
    if (!shuffled || !wraps || entries.length < 2) return withIndex(next);
    final order = [...spread(entries)];
    if (order.first == current) {
      order
        ..[0] = order[1]
        ..[1] = current!;
    }
    return PlayQueue(
      entries: order,
      source: source,
      repeat: repeat,
      original: original,
      nextKey: _nextKey,
    );
  }

  PlayQueue withRepeat(QueueRepeat r) => _copy(repeat: r);

  PlayQueue withIndex(int i) => _copy(index: i);

  PlayQueue jumpTo(int key) {
    final i = entries.indexWhere((e) => e.key == key);
    return i < 0 ? this : _copy(index: i);
  }

  PlayQueue insertNext(int trackId) {
    final entry = QueueEntry(_nextKey, trackId, queued: true);
    final unshuffled = original;
    if (isEmpty) {
      return _withNew(
        [entry],
        0,
        original: unshuffled == null ? null : [entry],
      );
    }
    List<QueueEntry>? inOriginal;
    if (unshuffled != null) {
      final at = unshuffled.indexWhere((e) => e.key == current!.key);
      inOriginal = [...unshuffled]..insert(at + 1, entry);
    }
    return _withNew(
      [...entries]..insert(index + 1, entry),
      index,
      original: inOriginal,
    );
  }

  PlayQueue append(int trackId) {
    final entry = QueueEntry(_nextKey, trackId, queued: true);
    final unshuffled = original;
    return _withNew(
      [...entries, entry],
      isEmpty ? 0 : index,
      original: unshuffled == null ? null : [...unshuffled, entry],
    );
  }

  /// Moves an upcoming entry; [from] and [to] are indices within [upcoming],
  /// [to] counted after [from] was taken out (ReorderableListView's
  /// `onReorderItem`).
  PlayQueue moveUpcoming(int from, int to) {
    final up = [...upcoming];
    if (from < 0 || from >= up.length) return this;
    final moved = up.removeAt(from);
    up.insert(to.clamp(0, up.length), moved);
    return _copy(entries: [...entries.sublist(0, index + 1), ...up]);
  }

  /// Removes the entry with [key]; the current entry cannot be removed.
  PlayQueue remove(int key) {
    final i = entries.indexWhere((e) => e.key == key);
    if (i < 0 || i == index) return this;
    return _without([...entries]..removeAt(i), i < index ? index - 1 : index);
  }

  /// While shuffled, the unshuffled order becomes what was played so far, so
  /// turning shuffle off afterwards brings no cleared song back.
  PlayQueue clearUpcoming() {
    if (isEmpty) return this;
    final kept = entries.sublist(0, index + 1);
    return PlayQueue(
      entries: kept,
      index: index,
      source: source,
      repeat: repeat,
      original: original == null ? null : kept,
      nextKey: _nextKey,
    );
  }

  /// Drops entries whose track id is not in [existing]. If the current entry
  /// goes, index points at the entry that followed it, or at the last
  /// remaining entry when none followed; `currentRemoved` is then true.
  ({PlayQueue queue, bool currentRemoved}) retain(Set<int> existing) {
    if (isEmpty) return (queue: this, currentRemoved: false);
    final kept = <QueueEntry>[];
    int? newIndex;
    for (final (i, e) in entries.indexed) {
      if (!existing.contains(e.trackId)) continue;
      if (i >= index) newIndex ??= kept.length;
      kept.add(e);
    }
    final currentRemoved = !existing.contains(entries[index].trackId);
    if (kept.isEmpty) {
      return (queue: _without(const [], 0), currentRemoved: true);
    }
    return (
      queue: _without(kept, newIndex ?? kept.length - 1),
      currentRemoved: currentRemoved,
    );
  }
}
