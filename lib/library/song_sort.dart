import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/sort_key.dart';

/// How the Songs tab is ordered.
enum SongSort { title, artist, album, added }

/// The word used in "N songs · sorted by …".
String sortLabel(SongSort s) => switch (s) {
  SongSort.title => 'title',
  SongSort.artist => 'artist',
  SongSort.album => 'album',
  SongSort.added => 'recently added',
};

String? _albumOf(Track t) {
  final a = t.album?.trim();
  return (a == null || a.isEmpty) ? null : a;
}

/// Missing numbers sort after present ones.
int _compareNumbers(int? a, int? b) {
  if (a == b) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

class _Keyed {
  _Keyed(this.track)
    : title = sortKey(displayTitle(track.title, track.originalName)),
      artist = sortKey(displayArtist(track.artist)),
      album = _albumOf(track) == null ? null : sortKey(_albumOf(track)!),
      albumArtist = sortKey(displayArtist(track.albumArtist ?? track.artist));

  final Track track;
  final String title;
  final String artist;
  final String? album;
  final String albumArtist;
}

int _byTitle(_Keyed a, _Keyed b) {
  final c = compareKeys(a.title, b.title);
  return c != 0 ? c : compareKeys(a.artist, b.artist);
}

/// Disc, track number, then title.
int _byPosition(_Keyed a, _Keyed b) {
  var c = _compareNumbers(a.track.discNumber, b.track.discNumber);
  if (c != 0) return c;
  c = _compareNumbers(a.track.trackNumber, b.track.trackNumber);
  return c != 0 ? c : _byTitle(a, b);
}

/// Album (missing last), album artist, then position.
int _byAlbum(_Keyed a, _Keyed b) {
  if (a.album == null || b.album == null) {
    if (a.album != b.album) return a.album == null ? 1 : -1;
  } else {
    var c = compareKeys(a.album!, b.album!);
    if (c != 0) return c;
    c = compareKeys(a.albumArtist, b.albumArtist);
    if (c != 0) return c;
  }
  return _byPosition(a, b);
}

int _byArtist(_Keyed a, _Keyed b) {
  final c = compareKeys(a.artist, b.artist);
  return c != 0 ? c : _byAlbum(a, b);
}

int _byAdded(_Keyed a, _Keyed b) {
  final c = b.track.addedAt.compareTo(a.track.addedAt);
  return c != 0 ? c : _byTitle(a, b);
}

/// Returns a new list in [sort] order; [descending] reverses all of it.
List<Track> sortSongs(
  List<Track> tracks,
  SongSort sort, {
  bool descending = false,
}) {
  final keyed = [for (final t in tracks) _Keyed(t)];
  keyed.sort(switch (sort) {
    SongSort.title => _byTitle,
    SongSort.artist => _byArtist,
    SongSort.album => _byAlbum,
    SongSort.added => _byAdded,
  });
  final sorted = [for (final k in keyed) k.track];
  return descending ? sorted.reversed.toList() : sorted;
}

/// The section header letter of [t] under [sort]; `null` when that sort has
/// no sections.
String? songSection(Track t, SongSort sort) => switch (sort) {
  SongSort.title => sectionLetter(displayTitle(t.title, t.originalName)),
  SongSort.artist => sectionLetter(displayArtist(t.artist)),
  SongSort.album => sectionLetter(_albumOf(t) ?? ''),
  SongSort.added => null,
};
