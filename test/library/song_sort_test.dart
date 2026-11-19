import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/library/song_sort.dart';

import '../support/fakes.dart';

void main() {
  test('title sort: title then artist, # last, input untouched', () {
    final input = [
      track(1, title: 'b'),
      track(2, title: 'The a'),
      track(3, title: '1999'),
      track(4, title: 'Ä c'),
    ];
    final sorted = sortSongs(input, SongSort.title);
    expect(sorted.map((t) => t.title), ['The a', 'Ä c', 'b', '1999']);
    expect(input.map((t) => t.id), [1, 2, 3, 4]);

    final tie = sortSongs([
      track(1, title: 'x', artist: 'Zed'),
      track(2, title: 'x', artist: 'Abe'),
    ], SongSort.title);
    expect(tie.map((t) => t.id), [2, 1]);
  });

  test('artist sort: artist, album, disc, track, title', () {
    final sorted = sortSongs([
      track(1, title: 'a', artist: 'Zed', album: 'A'),
      track(
        2,
        title: 'z',
        artist: 'Abe',
        album: 'B',
        discNumber: 1,
        trackNumber: 1,
      ),
      track(
        3,
        title: 'y',
        artist: 'Abe',
        album: 'A',
        discNumber: 2,
        trackNumber: 1,
      ),
      track(
        4,
        title: 'x',
        artist: 'Abe',
        album: 'A',
        discNumber: 1,
        trackNumber: 2,
      ),
      track(
        5,
        title: 'w',
        artist: 'Abe',
        album: 'A',
        discNumber: 1,
        trackNumber: 1,
      ),
    ], SongSort.artist);
    expect(sorted.map((t) => t.id), [5, 4, 3, 2, 1]);
  });

  test('album sort separates equal titles by album artist', () {
    final sorted = sortSongs([
      track(
        1,
        title: 'a1',
        artist: 'A',
        album: 'Greatest Hits',
        trackNumber: 1,
      ),
      track(
        2,
        title: 'b1',
        artist: 'B',
        album: 'Greatest Hits',
        trackNumber: 1,
      ),
      track(
        3,
        title: 'a2',
        artist: 'A',
        album: 'Greatest Hits',
        trackNumber: 2,
      ),
    ], SongSort.album);
    expect(sorted.map((t) => t.id), [1, 3, 2]);
  });

  test('album sort puts tracks without album last, after # albums', () {
    final sorted = sortSongs([
      track(1, title: 'x', album: '1989'),
      track(2, title: 'y'),
      track(3, title: 'z', album: 'Zed'),
    ], SongSort.album);
    expect(sorted.map((t) => t.id), [3, 1, 2]);
  });

  test('tracks without numbers come after numbered ones within an album', () {
    final sorted = sortSongs([
      track(1, title: 'a', album: 'X'),
      track(2, title: 'b', album: 'X', trackNumber: 5),
    ], SongSort.album);
    expect(sorted.map((t) => t.id), [2, 1]);
  });

  test('added: newest first ascending, oldest first descending', () {
    final tracks = [
      track(1, title: 'old', addedAt: DateTime(2026, 1, 1)),
      track(2, title: 'new', addedAt: DateTime(2026, 6, 1)),
    ];
    expect(sortSongs(tracks, SongSort.added).map((t) => t.id), [2, 1]);
    expect(
      sortSongs(tracks, SongSort.added, descending: true).map((t) => t.id),
      [1, 2],
    );
  });

  test('descending reverses the whole list', () {
    final sorted = sortSongs(
      [track(1, title: 'a'), track(2, title: '1'), track(3, title: 'b')],
      SongSort.title,
      descending: true,
    );
    expect(sorted.map((t) => t.id), [2, 3, 1]);
  });

  test('songSection', () {
    expect(songSection(track(1, title: 'the beatles'), SongSort.title), 'B');
    expect(songSection(track(1, title: 'x'), SongSort.album), '#');
    expect(
      songSection(track(1, title: 'x', album: 'Ember'), SongSort.album),
      'E',
    );
    expect(songSection(track(1, title: 'x'), SongSort.artist), 'U');
    expect(songSection(track(1, title: 'x'), SongSort.added), isNull);
  });

  test('sortLabel', () {
    expect(SongSort.values.map(sortLabel), [
      'title',
      'artist',
      'album',
      'recently added',
    ]);
  });
}
