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
/// rows are identified by [key], never by [trackId].
class QueueEntry {
  const QueueEntry(this.key, this.trackId);

  final int key;
  final int trackId;

  @override
  bool operator ==(Object other) =>
      other is QueueEntry && other.key == key && other.trackId == trackId;

  @override
  int get hashCode => Object.hash(key, trackId);
}

/// The play queue: entries, the current [index], where it was started
/// from ([source], e.g. an album title) and the [repeat] mode.
///
/// Immutable; every change returns a new queue. Entry keys are unique within
/// a queue and never reused.
class PlayQueue {
  const PlayQueue({
    this.entries = const [],
    this.index = 0,
    this.source,
    this.repeat = QueueRepeat.off,
    this._nextKey = 0,
  });

  static const empty = PlayQueue();

  factory PlayQueue.of(
    List<int> trackIds, {
    required int start,
    String? source,
    QueueRepeat repeat = QueueRepeat.off,
  }) => PlayQueue(
    entries: [for (final (i, id) in trackIds.indexed) QueueEntry(i, id)],
    index: start,
    source: source,
    repeat: repeat,
    nextKey: trackIds.length,
  );

  final List<QueueEntry> entries;
  final int index;
  final String? source;
  final QueueRepeat repeat;
  final int _nextKey;

  bool get isEmpty => entries.isEmpty;

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
    nextKey: _nextKey,
  );

  PlayQueue _withNew(List<QueueEntry> entries, int index) => PlayQueue(
    entries: entries,
    index: index,
    source: source,
    repeat: repeat,
    nextKey: _nextKey + 1,
  );

  PlayQueue withRepeat(QueueRepeat r) => _copy(repeat: r);

  PlayQueue withIndex(int i) => _copy(index: i);

  PlayQueue jumpTo(int key) {
    final i = entries.indexWhere((e) => e.key == key);
    return i < 0 ? this : _copy(index: i);
  }

  PlayQueue insertNext(int trackId) {
    final entry = QueueEntry(_nextKey, trackId);
    if (isEmpty) return _withNew([entry], 0);
    return _withNew([...entries]..insert(index + 1, entry), index);
  }

  PlayQueue append(int trackId) {
    final entry = QueueEntry(_nextKey, trackId);
    return _withNew([...entries, entry], isEmpty ? 0 : index);
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
    return _copy(
      entries: [...entries]..removeAt(i),
      index: i < index ? index - 1 : index,
    );
  }

  PlayQueue clearUpcoming() =>
      isEmpty ? this : _copy(entries: entries.sublist(0, index + 1));

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
      return (queue: _copy(entries: const [], index: 0), currentRemoved: true);
    }
    return (
      queue: _copy(entries: kept, index: newIndex ?? kept.length - 1),
      currentRemoved: currentRemoved,
    );
  }
}
