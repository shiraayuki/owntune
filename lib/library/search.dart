import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/sort_key.dart';

/// Matches of a search, grouped by type.
class SearchResults {
  const SearchResults({
    this.artists = const [],
    this.albums = const [],
    this.songs = const [],
  });

  final List<Artist> artists;
  final List<Album> albums;
  final List<Track> songs;

  bool get isEmpty => artists.isEmpty && albums.isEmpty && songs.isEmpty;
}

List<T> _sortedBy<T>(Iterable<T> items, String Function(T) name) {
  final keyed = [for (final i in items) (item: i, key: sortKey(name(i)))];
  keyed.sort((a, b) => compareKeys(a.key, b.key));
  return [for (final k in keyed) k.item];
}

bool _contains(String? s, String q) => s != null && foldKey(s).contains(q);

/// Whether [t] matches the folded query [q] (title, artist or album).
bool songMatches(Track t, String q) =>
    _contains(displayTitle(t.title, t.originalName), q) ||
    _contains(displayArtist(t.artist), q) ||
    _contains(t.album, q);

/// Whether [a] matches the folded query [q] (title or album artist).
bool albumMatches(Album a, String q) =>
    _contains(a.title, q) || _contains(a.artist, q);

/// Whether [a] matches the folded query [q] (name).
bool artistMatches(Artist a, String q) => _contains(a.name, q);

/// Substring search ignoring case and diacritics: artists by name, albums by
/// title or album artist, songs by title, artist or album. A blank [query]
/// finds nothing.
SearchResults searchLibrary(Library library, String query) {
  final q = foldKey(query);
  if (q.isEmpty) return const SearchResults();
  return SearchResults(
    artists: _sortedBy(
      library.artists.where((a) => artistMatches(a, q)),
      (a) => a.name,
    ),
    albums: _sortedBy(
      library.albums.where((a) => albumMatches(a, q)),
      (a) => a.title,
    ),
    songs: _sortedBy(
      library.tracks.where((t) => songMatches(t, q)),
      (t) => displayTitle(t.title, t.originalName),
    ),
  );
}
