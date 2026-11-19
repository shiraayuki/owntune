import 'dart:math';

/// Orders [items] so items with the same [artist] are spread evenly over the
/// list, and within one artist those of the same [album]; random offsets keep
/// it from looking regular. A plain shuffle often plays the same artist
/// several times in a row, which feels less random, not more.
///
/// Each group's items are placed at evenly spaced positions in [0, 1) with a
/// random start and a little jitter, then all items are merged by position
/// (the approach Spotify described for its shuffle).
List<T> spread<T>(
  List<T> items, {
  required Object? Function(T) artist,
  required Object? Function(T) album,
  required Random random,
}) {
  List<T> level(List<T> xs, List<Object? Function(T)> keys) {
    if (xs.length < 2) return [...xs];
    if (keys.isEmpty) return [...xs]..shuffle(random);
    final groups = <Object?, List<T>>{};
    for (final x in xs) {
      (groups[keys.first(x)] ??= []).add(x);
    }
    final placed = <(double, T)>[];
    for (final g in groups.values) {
      final ordered = level(g, keys.sublist(1));
      final n = ordered.length;
      final offset = random.nextDouble() / n;
      for (final (i, x) in ordered.indexed) {
        final jitter = (random.nextDouble() - 0.5) * 0.1 / n;
        placed.add((offset + i / n + jitter, x));
      }
    }
    placed.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final p in placed) p.$2];
  }

  return level(items, [artist, album]);
}
