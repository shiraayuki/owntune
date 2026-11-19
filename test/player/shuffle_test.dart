import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/player/shuffle.dart';

typedef Song = (int id, String artist, String album);

List<Song> order(List<Song> songs, int seed) => spread(
  songs,
  artist: (s) => s.$2,
  album: (s) => s.$3,
  random: Random(seed),
);

int neighbours(List<Song> songs, Object Function(Song) key) {
  var n = 0;
  for (var i = 1; i < songs.length; i++) {
    if (key(songs[i - 1]) == key(songs[i])) n++;
  }
  return n;
}

/// 3 artists × 4 songs, one album each.
final threeArtists = [
  for (var i = 0; i < 12; i++) (i, 'artist${i % 3}', 'album${i % 3}'),
];

void main() {
  test('keeps every item exactly once', () {
    final ids = [for (final s in order(threeArtists, 7)) s.$1]..sort();
    expect(ids, [for (var i = 0; i < 12; i++) i]);
  });

  test('spreads artists', () {
    var total = 0;
    for (var seed = 0; seed < 200; seed++) {
      total += neighbours(order(threeArtists, seed), (s) => s.$2);
    }
    // A plain shuffle gives about 600.
    expect(total, lessThanOrEqualTo(20));
  });

  test('spreads albums within one artist', () {
    final songs = [for (var i = 0; i < 8; i++) (i, 'artist', 'album${i % 2}')];
    var total = 0;
    for (var seed = 0; seed < 200; seed++) {
      total += neighbours(order(songs, seed), (s) => s.$3);
    }
    // A plain shuffle gives about 600.
    expect(total, lessThanOrEqualTo(60));
  });

  test('differs between seeds', () {
    expect(order(threeArtists, 1), isNot(order(threeArtists, 2)));
  });

  test('same seed, same order', () {
    expect(order(threeArtists, 3), order(threeArtists, 3));
  });

  test('zero and one item', () {
    expect(order(const [], 1), isEmpty);
    expect(order(const [(1, 'a', 'b')], 1), [(1, 'a', 'b')]);
  });
}
