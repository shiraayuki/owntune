import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/home/for_you.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/player/queue_source.dart';
import 'package:owntune/playlists/playlist_view.dart';

import '../support/fakes.dart';

void main() {
  final now = DateTime(2026, 11, 24, 20);

  PlaylistView playlist(int id, String name, DateTime createdAt) =>
      PlaylistView(
        id: id,
        name: name,
        coverFile: null,
        createdAt: createdAt,
        items: const [],
      );

  RecentSource recentOf(QueueSourceKind kind, String? key, [int minutes = 0]) =>
      RecentSource(kind, key, now.subtract(Duration(minutes: minutes)));

  String albumKey(String artist, String title) => '$artist\u0000$title';

  ForYou build({
    required List<Track> tracks,
    List<PlaylistView> playlists = const [],
    List<RecentSource> recent = const [],
    List<TrackPlayCount> topRecent = const [],
  }) => buildForYou(
    library: Library.from(tracks),
    playlists: playlists,
    liked: [
      for (final t in tracks)
        if (t.likedAt != null) t,
    ],
    recent: recent,
    topRecent: topRecent,
    now: now,
  );

  List<String> titles(ForYou f) => [for (final t in f.tiles) t.title];

  test('greeting boundaries', () {
    String at(int h, int m) => greeting(DateTime(2026, 11, 24, h, m));
    expect(at(4, 59), 'Good evening');
    expect(at(5, 0), 'Good morning');
    expect(at(11, 59), 'Good morning');
    expect(at(12, 0), 'Good afternoon');
    expect(at(17, 59), 'Good afternoon');
    expect(at(18, 0), 'Good evening');
  });

  test('tiles resolve recent sources in order', () {
    final tracks = [
      track(1, title: 'A1', artist: 'Ann', album: 'First'),
      track(2, title: 'B1', artist: 'Bob', album: 'Second', likedAt: now),
    ];
    final f = build(
      tracks: tracks,
      playlists: [playlist(7, 'Mix', DateTime(2026, 11, 1))],
      recent: [
        recentOf(QueueSourceKind.album, albumKey('ann', 'first')),
        recentOf(QueueSourceKind.playlist, '7'),
        recentOf(QueueSourceKind.liked, null),
        recentOf(QueueSourceKind.artist, 'bob'),
      ],
    );
    expect(f.tiles[0], isA<AlbumTile>());
    expect((f.tiles[0] as AlbumTile).album.title, 'First');
    expect(f.tiles[1], isA<PlaylistTile>());
    expect((f.tiles[1] as PlaylistTile).playlist.id, 7);
    expect(f.tiles[2], isA<LikedTile>());
    expect(f.tiles[2].title, 'Liked Songs');
    expect(f.tiles[3], isA<ArtistTile>());
    expect((f.tiles[3] as ArtistTile).artist.name, 'Bob');
  });

  test('renamed album drops out and fill-up takes its place', () {
    final tracks = [
      for (var i = 1; i <= 4; i++)
        track(
          i,
          title: 'S$i',
          artist: 'Artist $i',
          album: 'Album $i',
          addedAt: DateTime(2026, 11, i),
        ),
      track(
        5,
        title: 'L',
        artist: 'Liker',
        album: 'Liked Album',
        addedAt: DateTime(2026, 10, 1),
        likedAt: now,
      ),
    ];
    final f = build(
      tracks: tracks,
      playlists: [
        playlist(1, 'Old', DateTime(2026, 1, 1)),
        playlist(2, 'New', DateTime(2026, 6, 1)),
      ],
      recent: [
        recentOf(QueueSourceKind.album, albumKey('artist 1', 'album 1')),
        recentOf(QueueSourceKind.album, albumKey('artist 2', 'old name')),
        recentOf(QueueSourceKind.artist, 'nobody'),
        recentOf(QueueSourceKind.playlist, '999'),
        recentOf(QueueSourceKind.playlist, 'x'),
      ],
    );
    // Album 1, then fill-up: Liked, playlists newest created first, then
    // Recently Added albums without duplicates.
    expect(titles(f), [
      'Album 1',
      'Liked Songs',
      'New',
      'Old',
      'Album 4',
      'Album 3',
    ]);
    expect(f.tiles, hasLength(6));
  });

  test('fill-up does not repeat a Liked tile that is already shown', () {
    final f = build(
      tracks: [track(1, title: 'L', artist: 'A', album: 'X', likedAt: now)],
      recent: [recentOf(QueueSourceKind.liked, null)],
    );
    expect(titles(f), ['Liked Songs', 'X']);
  });

  test('Liked tile only when something is liked', () {
    final f = build(
      tracks: [track(1, title: 'S', artist: 'A')],
      recent: [recentOf(QueueSourceKind.liked, null)],
    );
    expect(f.tiles, isEmpty);
  });

  test('on repeat uses the 30-day counts', () {
    final tracks = [
      for (var i = 1; i <= 4; i++) track(i, title: 'S$i', artist: 'A'),
    ];
    final f = build(
      tracks: tracks,
      topRecent: const [
        TrackPlayCount(3, 9),
        TrackPlayCount(99, 8),
        TrackPlayCount(1, 5),
        TrackPlayCount(4, 2),
        TrackPlayCount(2, 1),
      ],
    );
    expect([for (final c in f.onRepeat) c.track.id], [3, 1, 4, 2]);
    expect(
      [for (final c in f.onRepeat) c.subtitle],
      ['9 plays', '5 plays', '2 plays', '1 play'],
    );
  });

  test('on repeat falls back to all-time play counts below 4 songs', () {
    final tracks = [
      track(1, title: 'S1', artist: 'A', playCount: 3),
      track(2, title: 'S2', artist: 'A', playCount: 7),
      track(
        3,
        title: 'S3',
        artist: 'A',
        playCount: 3,
        lastPlayedAt: DateTime(2026, 11, 20),
      ),
      track(
        4,
        title: 'S4',
        artist: 'A',
        playCount: 3,
        lastPlayedAt: DateTime(2026, 11, 22),
      ),
      track(5, title: 'S5', artist: 'A', playCount: 1),
      track(6, title: 'S6', artist: 'A'),
    ];
    final f = build(
      tracks: tracks,
      topRecent: const [TrackPlayCount(1, 2), TrackPlayCount(2, 1)],
    );
    expect([for (final c in f.onRepeat) c.track.id], [2, 4, 3, 1, 5]);
    expect(
      [for (final c in f.onRepeat) c.subtitle],
      ['7 plays', '3 plays', '3 plays', '3 plays', '1 play'],
    );
  });

  test('recently added orders albums by their newest track', () {
    final tracks = [
      track(1, album: 'Old', artist: 'A', addedAt: DateTime(2026, 1, 1)),
      track(2, album: 'Mixed', artist: 'B', addedAt: DateTime(2026, 2, 1)),
      track(3, album: 'Mixed', artist: 'B', addedAt: DateTime(2026, 11, 1)),
      track(4, album: 'Mid', artist: 'C', addedAt: DateTime(2026, 6, 1)),
      track(5, artist: 'D', addedAt: DateTime(2026, 12, 1)),
    ];
    final f = build(tracks: tracks);
    expect([for (final a in f.recentlyAdded) a.title], ['Mixed', 'Mid', 'Old']);
  });

  test('recently added breaks ties by the highest track id in the album', () {
    final same = DateTime(2026, 5, 1);
    final tracks = [
      track(7, album: 'Low', artist: 'A', addedAt: same),
      track(9, album: 'High', artist: 'B', addedAt: same),
      track(3, album: 'High', artist: 'B', addedAt: same),
      track(8, album: 'Mid', artist: 'C', addedAt: same),
      track(1, album: 'Older', artist: 'D', addedAt: DateTime(2026, 4, 1)),
    ];
    final f = build(tracks: tracks);
    expect(
      [for (final a in f.recentlyAdded) a.title],
      ['High', 'Mid', 'Low', 'Older'],
    );
  });

  test('one play is singular in the on repeat subtitle', () {
    final tracks = [track(1, title: 'S1', artist: 'A', playCount: 1)];
    final f = build(tracks: tracks);
    expect([for (final c in f.onRepeat) c.subtitle], ['1 play']);
    final g = build(
      tracks: [for (var i = 1; i <= 4; i++) track(i, artist: 'A')],
      topRecent: const [
        TrackPlayCount(1, 1),
        TrackPlayCount(2, 1),
        TrackPlayCount(3, 2),
        TrackPlayCount(4, 1),
      ],
    );
    expect(
      [for (final c in g.onRepeat) c.subtitle],
      ['1 play', '1 play', '2 plays', '1 play'],
    );
  });

  test('rediscover thresholds', () {
    DateTime ago(int days) => now.subtract(Duration(days: days));
    final tracks = [
      track(1, title: 'In61', playCount: 3, lastPlayedAt: ago(61)),
      track(2, title: 'TwoPlays', playCount: 2, lastPlayedAt: ago(200)),
      track(3, title: 'Exactly60', playCount: 5, lastPlayedAt: ago(60)),
      track(4, title: 'In125', playCount: 9, lastPlayedAt: ago(125)),
      track(5, title: 'Never', playCount: 4),
    ];
    final f = build(tracks: tracks);
    expect([for (final c in f.rediscover) c.track.id], [4, 1]);
    expect(
      [for (final c in f.rediscover) c.subtitle],
      ['Last played 4 mo ago', 'Last played 2 mo ago'],
    );
  });

  test('never played is newest added first', () {
    final tracks = [
      track(1, title: 'Old', artist: 'Ann', addedAt: DateTime(2026, 1, 1)),
      track(2, title: 'New', artist: 'Bob', addedAt: DateTime(2026, 11, 1)),
      track(3, title: 'Played', artist: 'Cy', playCount: 1),
      track(4, title: 'Mid', addedAt: DateTime(2026, 6, 1)),
    ];
    final f = build(tracks: tracks);
    expect([for (final c in f.neverPlayed) c.track.id], [2, 4, 1]);
    expect(
      [for (final c in f.neverPlayed) c.subtitle],
      ['Bob', 'Unknown Artist', 'Ann'],
    );
  });

  test('young library without history', () {
    final tracks = [
      track(1, title: 'A', artist: 'Ann', album: 'One'),
      track(2, title: 'B', artist: 'Bob'),
    ];
    final f = build(tracks: tracks);
    expect(titles(f), ['One']);
    expect(f.onRepeat, isEmpty);
    expect(f.rediscover, isEmpty);
    expect(f.neverPlayed, hasLength(2));
    expect(f.isEmpty, isFalse);
  });

  test('empty library gives an empty ForYou', () {
    expect(build(tracks: const []).isEmpty, isTrue);
  });

  test('lists are capped at 50', () {
    final tracks = [
      for (var i = 1; i <= 60; i++)
        track(
          i,
          title: 'S$i',
          artist: 'Artist $i',
          album: 'Album $i',
          playCount: 3,
          lastPlayedAt: now.subtract(const Duration(days: 100)),
        ),
      for (var i = 61; i <= 120; i++) track(i, title: 'N$i', artist: 'X'),
    ];
    final f = build(
      tracks: tracks,
      topRecent: [for (var i = 1; i <= 60; i++) TrackPlayCount(i, 100 - i)],
    );
    expect(f.onRepeat, hasLength(50));
    expect(f.recentlyAdded, hasLength(50));
    expect(f.rediscover, hasLength(50));
    expect(f.neverPlayed, hasLength(50));
    expect(f.tiles.length, lessThanOrEqualTo(6));
    expect(homeRowLimit, 10);
    expect(homeListLimit, 50);
  });
}
