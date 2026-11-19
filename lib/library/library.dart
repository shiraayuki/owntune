import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/song_sort.dart';
import 'package:owntune/library/sort_key.dart';

/// Identity of an album: album artist group key and lowercased title.
typedef AlbumKey = ({String artist, String title});

/// Group key of an artist name; blank and missing names share the
/// "Unknown Artist" group. Used for both artists and album artists.
String artistGroupKey(String? name) => displayArtist(name).trim().toLowerCase();

String? _blankToNull(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// The album [t] belongs to, or `null` when its album tag is blank.
AlbumKey? albumKeyOf(Track t) {
  final album = _blankToNull(t.album);
  if (album == null) return null;
  return (
    artist: artistGroupKey(_blankToNull(t.albumArtist) ?? t.artist),
    title: album.toLowerCase(),
  );
}

/// The most frequent non-null value; on a tie, the one for which
/// [prefer] returns true against the current best.
T? _mostCommon<T extends Object>(
  Iterable<T?> values,
  bool Function(T candidate, T best) prefer,
) {
  final counts = <T, int>{};
  for (final v in values) {
    if (v != null) counts[v] = (counts[v] ?? 0) + 1;
  }
  T? best;
  var bestCount = 0;
  counts.forEach((v, n) {
    if (best == null || n > bestCount || (n == bestCount && prefer(v, best!))) {
      best = v;
      bestCount = n;
    }
  });
  return best;
}

/// An album derived from track tags.
class Album {
  const Album({
    required this.key,
    required this.title,
    required this.artist,
    required this.year,
    required this.genre,
    required this.coverFile,
    required this.tracks,
  });

  factory Album._from(AlbumKey key, List<Track> tracks) {
    final sorted = sortSongs(tracks, SongSort.album);
    final first = sorted.first;
    return Album(
      key: key,
      title: _blankToNull(first.album)!,
      artist: displayArtist(_blankToNull(first.albumArtist) ?? first.artist),
      year: _mostCommon(sorted.map((t) => t.year), (a, b) => a > b),
      genre: _mostCommon(
        sorted.map((t) => _blankToNull(t.genre)),
        (a, b) => a.compareTo(b) < 0,
      ),
      coverFile: sorted
          .map((t) => t.coverFile)
          .firstWhere((c) => c != null, orElse: () => null),
      tracks: sorted,
    );
  }

  final AlbumKey key;

  /// Spellings of the first track.
  final String title;
  final String artist;

  /// Most common year (ties: later) and genre (ties: alphabetical first).
  final int? year;
  final String? genre;

  /// Cover of the first track that has one.
  final String? coverFile;

  /// Ordered by disc, track number, title.
  final List<Track> tracks;

  bool get hasMultipleDiscs =>
      tracks.map((t) => t.discNumber).toSet().length > 1;
}

/// An artist derived from the track artist tag.
class Artist {
  const Artist({
    required this.key,
    required this.name,
    required this.songs,
    required this.albums,
    required this.avatarCover,
  });

  final String key;

  /// Spelling of the first song by title.
  final String name;

  /// Tracks with this track artist, by title.
  final List<Track> songs;

  /// Albums with this album artist: year descending, unknown year last, then
  /// title.
  final List<Album> albums;

  /// Cover of the newest album that has one, else of any song.
  final String? avatarCover;
}

int _byYearDesc(Album a, Album b) {
  if (a.year != b.year) {
    if (a.year == null) return 1;
    if (b.year == null) return -1;
    return b.year!.compareTo(a.year!);
  }
  return compareKeys(sortKey(a.title), sortKey(b.title));
}

/// Songs, albums and artists of the library, derived from the tracks.
class Library {
  Library._(this.tracks, this.albums, this.artists)
    : _albumsByKey = {for (final a in albums) a.key: a},
      _artistsByKey = {for (final a in artists) a.key: a};

  factory Library.from(List<Track> tracks) {
    final albumTracks = <AlbumKey, List<Track>>{};
    final artistTracks = <String, List<Track>>{};
    for (final t in tracks) {
      final key = albumKeyOf(t);
      if (key != null) (albumTracks[key] ??= []).add(t);
      (artistTracks[artistGroupKey(t.artist)] ??= []).add(t);
    }

    final albums = [
      for (final e in albumTracks.entries) Album._from(e.key, e.value),
    ];
    albums.sort((a, b) {
      final c = compareKeys(sortKey(a.artist), sortKey(b.artist));
      return c != 0 ? c : compareKeys(sortKey(a.title), sortKey(b.title));
    });

    final albumsByArtist = <String, List<Album>>{};
    for (final a in albums) {
      (albumsByArtist[a.key.artist] ??= []).add(a);
    }

    final artists = [
      for (final e in artistTracks.entries)
        _artist(e.key, e.value, albumsByArtist[e.key] ?? const []),
    ];
    artists.sort((a, b) => compareKeys(sortKey(a.name), sortKey(b.name)));

    return Library._(List.unmodifiable(tracks), albums, artists);
  }

  static Artist _artist(String key, List<Track> tracks, List<Album> albums) {
    final songs = sortSongs(tracks, SongSort.title);
    final sortedAlbums = [...albums]..sort(_byYearDesc);
    final cover =
        sortedAlbums
            .map((a) => a.coverFile)
            .firstWhere((c) => c != null, orElse: () => null) ??
        songs
            .map((t) => t.coverFile)
            .firstWhere((c) => c != null, orElse: () => null);
    return Artist(
      key: key,
      name: displayArtist(songs.first.artist),
      songs: songs,
      albums: sortedAlbums,
      avatarCover: cover,
    );
  }

  static final empty = Library.from(const []);

  /// As given, unsorted.
  final List<Track> tracks;

  /// By album artist, then title.
  final List<Album> albums;

  /// By name.
  final List<Artist> artists;

  final Map<AlbumKey, Album> _albumsByKey;
  final Map<String, Artist> _artistsByKey;

  Album? album(AlbumKey key) => _albumsByKey[key];

  Artist? artist(String key) => _artistsByKey[key];

  bool get isEmpty => tracks.isEmpty;
}
