import 'dart:math' as math;

import 'package:owntune/data/db/database.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/queue_source.dart';
import 'package:owntune/playlists/playlist_view.dart';

/// Songs a Home row shows; "›" opens the full list.
const homeRowLimit = 10;

/// Items of a full list page and of each section's data.
const homeListLimit = 50;

const _tileLimit = 6;
const _onRepeatMinimum = 4;
const _rediscoverMinPlays = 3;
const _rediscoverAfterDays = 60;

/// A shortcut tile at the top of For You.
sealed class HomeTile {
  String get title;
}

final class AlbumTile extends HomeTile {
  AlbumTile(this.album);

  final Album album;

  @override
  String get title => album.title;
}

final class ArtistTile extends HomeTile {
  ArtistTile(this.artist);

  final Artist artist;

  @override
  String get title => artist.name;
}

final class PlaylistTile extends HomeTile {
  PlaylistTile(this.playlist);

  final PlaylistView playlist;

  @override
  String get title => playlist.name;
}

final class LikedTile extends HomeTile {
  @override
  String get title => 'Liked Songs';
}

/// A song with the line shown under its title.
class SongCard {
  const SongCard(this.track, this.subtitle);

  final Track track;
  final String subtitle;
}

/// The content of the For You sub-tab.
class ForYou {
  const ForYou({
    required this.tiles,
    required this.onRepeat,
    required this.recentlyAdded,
    required this.rediscover,
    required this.neverPlayed,
  });

  /// At most six.
  final List<HomeTile> tiles;

  /// At most [homeListLimit]; rows show the first [homeRowLimit].
  final List<SongCard> onRepeat;
  final List<Album> recentlyAdded;
  final List<SongCard> rediscover;
  final List<SongCard> neverPlayed;

  bool get isEmpty =>
      tiles.isEmpty &&
      onRepeat.isEmpty &&
      recentlyAdded.isEmpty &&
      rediscover.isEmpty &&
      neverPlayed.isEmpty;
}

/// "Good morning" from 05:00, "Good afternoon" from 12:00, "Good evening"
/// from 18:00 until 04:59.
String greeting(DateTime now) {
  if (now.hour >= 18 || now.hour < 5) return 'Good evening';
  if (now.hour >= 12) return 'Good afternoon';
  return 'Good morning';
}

/// Combines the library, playlists, liked songs and the play history into the
/// For You sections. Sources that no longer resolve (deleted, renamed) are
/// skipped.
ForYou buildForYou({
  required Library library,
  required List<PlaylistView> playlists,
  required List<Track> liked,
  required List<RecentSource> recent,
  required List<TrackPlayCount> topRecent,
  required DateTime now,
}) {
  final recentlyAdded = _recentlyAdded(library);
  return ForYou(
    tiles: _tiles(library, playlists, liked, recent, recentlyAdded),
    onRepeat: _onRepeat(library, topRecent),
    recentlyAdded: recentlyAdded.take(homeListLimit).toList(),
    rediscover: _rediscover(library, now),
    neverPlayed: _neverPlayed(library),
  );
}

String _plays(int n) => n == 1 ? '1 play' : '$n plays';

/// Albums by their newest track, newest first. `addedAt` is stored in whole
/// seconds, so ties are common; the album with the highest track id wins.
List<Album> _recentlyAdded(Library library) {
  DateTime newest(Album a) =>
      a.tracks.map((t) => t.addedAt).reduce((a, b) => a.isAfter(b) ? a : b);
  int highestId(Album a) => a.tracks.map((t) => t.id).reduce(math.max);
  final newestOf = {for (final a in library.albums) a: newest(a)};
  final highestOf = {for (final a in library.albums) a: highestId(a)};
  return [...library.albums]..sort((a, b) {
    final c = newestOf[b]!.compareTo(newestOf[a]!);
    return c != 0 ? c : highestOf[b]!.compareTo(highestOf[a]!);
  });
}

AlbumKey? _parseAlbumKey(String? key) {
  if (key == null) return null;
  final parts = key.split('\u0000');
  if (parts.length != 2) return null;
  return (artist: parts[0], title: parts[1]);
}

List<HomeTile> _tiles(
  Library library,
  List<PlaylistView> playlists,
  List<Track> liked,
  List<RecentSource> recent,
  List<Album> recentlyAdded,
) {
  final tiles = <HomeTile>[];
  final seen = <Object>{};

  void add(Object identity, HomeTile Function() tile) {
    if (tiles.length >= _tileLimit || !seen.add(identity)) return;
    tiles.add(tile());
  }

  void addLiked() {
    if (liked.isNotEmpty) add('liked', LikedTile.new);
  }

  void addAlbum(Album a) => add(a.key, () => AlbumTile(a));
  void addPlaylist(PlaylistView p) =>
      add(('playlist', p.id), () => PlaylistTile(p));

  final playlistsById = {for (final p in playlists) p.id: p};
  for (final r in recent) {
    switch (r.kind) {
      case QueueSourceKind.album:
        final key = _parseAlbumKey(r.key);
        final album = key == null ? null : library.album(key);
        if (album != null) addAlbum(album);
      case QueueSourceKind.artist:
        final artist = r.key == null ? null : library.artist(r.key!);
        if (artist != null) {
          add(('artist', artist.key), () => ArtistTile(artist));
        }
      case QueueSourceKind.playlist:
        final id = r.key == null ? null : int.tryParse(r.key!);
        final playlist = id == null ? null : playlistsById[id];
        if (playlist != null) addPlaylist(playlist);
      case QueueSourceKind.liked:
        addLiked();
      case QueueSourceKind.songs ||
          QueueSourceKind.search ||
          QueueSourceKind.queued ||
          QueueSourceKind.other:
        break;
    }
  }

  // Fill-up: Liked Songs, playlists (newest created first), albums (newest
  // added first).
  addLiked();
  for (final p in [
    ...playlists,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt))) {
    addPlaylist(p);
  }
  recentlyAdded.forEach(addAlbum);
  return tiles;
}

List<SongCard> _onRepeat(Library library, List<TrackPlayCount> topRecent) {
  final byId = {for (final t in library.tracks) t.id: t};
  final recentCards = [
    for (final c in topRecent)
      if (byId[c.trackId] case final t?) SongCard(t, _plays(c.plays)),
  ];
  if (recentCards.length >= _onRepeatMinimum) {
    return recentCards.take(homeListLimit).toList();
  }

  final played = [
    for (final t in library.tracks)
      if (t.playCount > 0) t,
  ];
  played.sort((a, b) {
    final c = b.playCount.compareTo(a.playCount);
    if (c != 0) return c;
    final x = a.lastPlayedAt;
    final y = b.lastPlayedAt;
    if (x != null && y != null) return y.compareTo(x);
    if (x != null) return -1;
    if (y != null) return 1;
    return 0;
  });
  return [
    for (final t in played.take(homeListLimit))
      SongCard(t, _plays(t.playCount)),
  ];
}

List<SongCard> _rediscover(Library library, DateTime now) {
  final songs = [
    for (final t in library.tracks)
      if (t.playCount >= _rediscoverMinPlays &&
          t.lastPlayedAt != null &&
          now.difference(t.lastPlayedAt!).inDays > _rediscoverAfterDays)
        t,
  ];
  songs.sort((a, b) {
    final c = b.playCount.compareTo(a.playCount);
    return c != 0 ? c : a.lastPlayedAt!.compareTo(b.lastPlayedAt!);
  });
  return [
    for (final t in songs.take(homeListLimit))
      SongCard(t, 'Last played ${_monthsAgo(now, t.lastPlayedAt!)} mo ago'),
  ];
}

int _monthsAgo(DateTime now, DateTime playedAt) {
  final months = now.difference(playedAt).inDays ~/ 30;
  return months < 2 ? 2 : months;
}

List<SongCard> _neverPlayed(Library library) {
  final songs = [
    for (final t in library.tracks)
      if (t.playCount == 0) t,
  ];
  songs.sort((a, b) {
    final c = b.addedAt.compareTo(a.addedAt);
    return c != 0 ? c : b.id.compareTo(a.id);
  });
  return [
    for (final t in songs.take(homeListLimit))
      SongCard(t, displayArtist(t.artist)),
  ];
}
