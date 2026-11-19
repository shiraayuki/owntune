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

/// Substring search ignoring case and diacritics: artists by name, albums by
/// title or album artist, songs by title, artist or album. A blank [query]
/// finds nothing.
SearchResults searchLibrary(Library library, String query) {
  final q = foldKey(query);
  if (q.isEmpty) return const SearchResults();
  bool matches(String? s) => s != null && foldKey(s).contains(q);

  return SearchResults(
    artists: _sortedBy(
      library.artists.where((a) => matches(a.name)),
      (a) => a.name,
    ),
    albums: _sortedBy(
      library.albums.where((a) => matches(a.title) || matches(a.artist)),
      (a) => a.title,
    ),
    songs: _sortedBy(
      library.tracks.where(
        (t) =>
            matches(displayTitle(t.title, t.originalName)) ||
            matches(displayArtist(t.artist)) ||
            matches(t.album),
      ),
      (t) => displayTitle(t.title, t.originalName),
    ),
  );
}
