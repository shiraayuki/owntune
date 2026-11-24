import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/library.dart';

/// One song at one position of a playlist.
class PlaylistItem {
  const PlaylistItem({required this.entryId, required this.track});

  final int entryId;
  final Track track;
}

/// A playlist with its entries resolved against the library.
class PlaylistView {
  const PlaylistView({
    required this.id,
    required this.name,
    required this.coverFile,
    required this.createdAt,
    required this.items,
  });

  final int id;
  final String name;
  final String? coverFile;
  final DateTime createdAt;

  /// By position; entries whose song is gone from the library are left out.
  final List<PlaylistItem> items;

  List<Track> get tracks => [for (final i in items) i.track];

  int get durationMs => items.fold(0, (sum, i) => sum + i.track.durationMs);

  /// Covers of the first four distinct albums (by item order) that have one.
  /// A song without an album counts by its own cover.
  List<String> get mosaicCovers {
    final seen = <Object>{};
    final covers = <String>[];
    for (final item in items) {
      final cover = item.track.coverFile;
      if (cover == null) continue;
      if (!seen.add(albumKeyOf(item.track) ?? cover)) continue;
      covers.add(cover);
      if (covers.length == 4) break;
    }
    return covers;
  }

  /// "18 songs · 1 h 7 min".
  String get meta {
    final n = items.length;
    return '$n ${n == 1 ? 'song' : 'songs'} · '
        '${formatTotalDuration(durationMs)}';
  }
}

/// "44 min", or "1 h 7 min" from one hour on; minutes are rounded down.
String formatTotalDuration(int ms) {
  final minutes = ms ~/ 60000;
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}

/// The playlists with their songs, newest first (ties: higher id first).
List<PlaylistView> resolvePlaylists(
  List<Playlist> playlists,
  List<PlaylistEntry> entries,
  List<Track> tracks,
) {
  final byId = {for (final t in tracks) t.id: t};
  final byPlaylist = <int, List<PlaylistEntry>>{};
  for (final e in entries) {
    (byPlaylist[e.playlistId] ??= []).add(e);
  }
  final views = [
    for (final p in playlists)
      PlaylistView(
        id: p.id,
        name: p.name,
        coverFile: p.coverFile,
        createdAt: p.createdAt,
        items: [
          for (final e in _byPosition(byPlaylist[p.id]))
            if (byId[e.trackId] case final t?)
              PlaylistItem(entryId: e.id, track: t),
        ],
      ),
  ];
  views.sort((a, b) {
    final c = b.createdAt.compareTo(a.createdAt);
    return c != 0 ? c : b.id.compareTo(a.id);
  });
  return views;
}

List<PlaylistEntry> _byPosition(List<PlaylistEntry>? entries) =>
    [...?entries]..sort(
      (a, b) => a.position != b.position
          ? a.position.compareTo(b.position)
          : a.id.compareTo(b.id),
    );
