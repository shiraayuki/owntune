import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/library/library.dart';

import '../support/fakes.dart';

void main() {
  test('groups by album artist + title, case-insensitive', () {
    final lib = Library.from([
      track(
        1,
        title: 'b',
        artist: 'Neon Harbor',
        album: 'velvet hours',
        trackNumber: 2,
      ),
      track(
        2,
        title: 'a',
        artist: 'Neon Harbor',
        album: 'Velvet Hours',
        trackNumber: 1,
      ),
    ]);
    expect(lib.albums, hasLength(1));
    final album = lib.albums.single;
    expect(album.title, 'Velvet Hours');
    expect(album.artist, 'Neon Harbor');
    expect(album.tracks.map((t) => t.id), [2, 1]);
  });

  test('equal titles by different album artists are two albums', () {
    final lib = Library.from([
      track(1, title: 'x', artist: 'B', album: 'Greatest Hits'),
      track(2, title: 'y', artist: 'A', album: 'Greatest Hits'),
    ]);
    expect(lib.albums.map((a) => a.artist), ['A', 'B']);
  });

  test('album artist falls back to artist, then Unknown Artist', () {
    final lib = Library.from([
      track(
        1,
        title: 'a',
        artist: 'Juno Vale',
        album: 'Ember',
        albumArtist: ' ',
      ),
      track(2, title: 'b', album: 'Loose'),
      track(
        3,
        title: 'c',
        artist: 'Mira Sol',
        albumArtist: 'Various',
        album: 'Mix',
      ),
    ]);
    expect(lib.albums.map((a) => '${a.title}/${a.artist}'), [
      'Ember/Juno Vale',
      'Loose/Unknown Artist',
      'Mix/Various',
    ]);
  });

  test('tracks without album are in no album but in their artist', () {
    final lib = Library.from([
      track(1, title: 'a', artist: 'Lumen Kids', album: '  '),
    ]);
    expect(lib.albums, isEmpty);
    expect(lib.artists.single.songs.single.id, 1);
  });

  test('year, genre and cover of an album', () {
    final lib = Library.from([
      track(
        1,
        title: 'a',
        album: 'X',
        trackNumber: 1,
        year: 2020,
        genre: 'Pop',
      ),
      track(
        2,
        title: 'b',
        album: 'X',
        trackNumber: 2,
        year: 2021,
        genre: 'Folk',
        cover: 'c2.jpg',
      ),
      track(
        3,
        title: 'c',
        album: 'X',
        trackNumber: 3,
        year: 2020,
        genre: 'Folk',
        cover: 'c3.jpg',
      ),
      track(
        4,
        title: 'd',
        album: 'X',
        trackNumber: 4,
        year: 2021,
        genre: 'Pop',
      ),
    ]);
    final album = lib.albums.single;
    expect(album.year, 2021); // tie between 2020 and 2021 → later
    expect(album.genre, 'Folk'); // tie → alphabetical first
    expect(album.coverFile, 'c2.jpg');
    expect(album.hasMultipleDiscs, isFalse);
  });

  test('multiple discs', () {
    final lib = Library.from([
      track(1, title: 'a', album: 'X', discNumber: 1),
      track(2, title: 'b', album: 'X', discNumber: 2),
    ]);
    expect(lib.albums.single.hasMultipleDiscs, isTrue);
  });

  test('artist albums use the album artist', () {
    final lib = Library.from([
      track(
        1,
        title: 'Cassette Summer',
        artist: 'Lumen Kids',
        album: 'Summer \'24',
        albumArtist: 'Various Artists',
      ),
      track(2, title: 'x', artist: 'Juno Vale', album: 'Ember'),
    ]);
    final lumen = lib.artist(artistGroupKey('Lumen Kids'))!;
    expect(lumen.songs, hasLength(1));
    expect(lumen.albums, isEmpty);
    expect(lib.artists.map((a) => a.name), ['Juno Vale', 'Lumen Kids']);
    expect(lib.albums.map((a) => a.title), contains('Summer \'24'));
  });

  test('artist albums order: year desc, unknown last, then title', () {
    final lib = Library.from([
      track(1, title: 'a', artist: 'N', album: 'Old', year: 2019),
      track(2, title: 'b', artist: 'N', album: 'None'),
      track(3, title: 'c', artist: 'N', album: 'New', year: 2023),
      track(4, title: 'd', artist: 'N', album: 'Also New', year: 2023),
    ]);
    expect(lib.artists.single.albums.map((a) => a.title), [
      'Also New',
      'New',
      'Old',
      'None',
    ]);
  });

  test('avatarCover prefers the newest album with a cover', () {
    final lib = Library.from([
      track(
        1,
        title: 'a',
        artist: 'N',
        album: 'Old',
        year: 2019,
        cover: 'old.jpg',
      ),
      track(
        2,
        title: 'b',
        artist: 'N',
        album: 'New',
        year: 2023,
        cover: 'new.jpg',
      ),
      track(3, title: 'c', artist: 'M', cover: 'single.jpg'),
    ]);
    expect(lib.artist(artistGroupKey('N'))!.avatarCover, 'new.jpg');
    expect(lib.artist(artistGroupKey('M'))!.avatarCover, 'single.jpg');
  });

  test(
    'Unknown Artist groups blank and missing artists and owns their albums',
    () {
      final lib = Library.from([
        track(1, title: 'a'),
        track(2, title: 'b', artist: '  ', album: 'Loose'),
      ]);
      final unknown = lib.artist(artistGroupKey(null))!;
      expect(unknown.name, 'Unknown Artist');
      expect(unknown.songs, hasLength(2));
      expect(unknown.albums.single.title, 'Loose');
    },
  );

  test('artists sort by sortKey with # last, songs by title', () {
    final lib = Library.from([
      track(1, title: 'z', artist: 'The Quiet Coast'),
      track(2, title: 'a', artist: 'Neon Harbor'),
      track(3, title: 'b', artist: '2Pac'),
      track(4, title: 'b', artist: 'neon harbor'),
    ]);
    expect(lib.artists.map((a) => a.name), [
      'Neon Harbor',
      'The Quiet Coast',
      '2Pac',
    ]);
    expect(lib.artists.first.songs.map((t) => t.id), [2, 4]);
  });

  test('lookups return null for unknown keys', () {
    final lib = Library.from([track(1, title: 'a', album: 'X')]);
    expect(lib.album((artist: 'nobody', title: 'x')), isNull);
    expect(lib.artist('nobody'), isNull);
    expect(lib.album(albumKeyOf(lib.tracks.single)!), isNotNull);
    expect(Library.empty.isEmpty, isTrue);
  });
}
