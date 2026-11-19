import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/search.dart';

import '../support/fakes.dart';

void main() {
  final library = Library.from([
    track(1, title: 'Grüße aus Köln', artist: 'Ärzte & Söhne'),
    track(
      2,
      title: 'Blue Hour',
      artist: 'The Quiet Coast',
      album: 'Low Tide Radio',
    ),
    track(
      3,
      title: 'Amber Lights',
      artist: 'Neon Harbor',
      album: 'Velvet Hours',
    ),
    track(4, title: 'Static', artist: 'Neon Harbor', album: 'Midnight Static'),
    track(5, title: 'Neon Swimmers', artist: 'Lumen Kids'),
  ]);

  List<String> artists(SearchResults r) => [for (final a in r.artists) a.name];
  List<String> albums(SearchResults r) => [for (final a in r.albums) a.title];
  List<String?> songs(SearchResults r) => [for (final t in r.songs) t.title];

  test('spaces and accents are ignored', () {
    final r = searchLibrary(library, '  arzte ');
    expect(artists(r), ['Ärzte & Söhne']);
    expect(songs(r), ['Grüße aus Köln']);
  });

  test('a leading "the" is part of the query', () {
    final r = searchLibrary(library, 'the quiet');
    expect(artists(r), ['The Quiet Coast']);
    expect(albums(r), ['Low Tide Radio']);
    expect(songs(r), ['Blue Hour']);
  });

  test('case-insensitive, also for umlauts', () {
    expect(songs(searchLibrary(library, 'KÖLN')), ['Grüße aus Köln']);
  });

  test('matches artists, albums by artist and songs by artist (mockup 10)', () {
    final r = searchLibrary(library, 'neon');
    expect(artists(r), ['Neon Harbor']);
    expect(albums(r), ['Midnight Static', 'Velvet Hours']);
    expect(songs(r), ['Amber Lights', 'Neon Swimmers', 'Static']);
  });

  test('songs match on their album', () {
    expect(songs(searchLibrary(library, 'tide')), ['Blue Hour']);
  });

  test('a blank query finds nothing', () {
    expect(searchLibrary(library, '   ').isEmpty, isTrue);
    expect(searchLibrary(library, '').isEmpty, isTrue);
    expect(searchLibrary(library, 'zzz').isEmpty, isTrue);
  });
}
