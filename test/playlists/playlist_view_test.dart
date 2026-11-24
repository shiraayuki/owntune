import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/playlists/playlist_view.dart';

import '../support/fakes.dart';

Playlist playlist(int id, {String name = 'Mix', DateTime? createdAt}) =>
    Playlist(
      id: id,
      name: name,
      coverFile: null,
      createdAt: createdAt ?? DateTime(2026, 11, 24),
    );

PlaylistEntry entry(int id, int playlistId, int trackId, int position) =>
    PlaylistEntry(
      id: id,
      playlistId: playlistId,
      trackId: trackId,
      position: position,
    );

void main() {
  test('resolvePlaylists drops entries of deleted tracks', () {
    final views = resolvePlaylists(
      [playlist(1)],
      [entry(1, 1, 10, 0), entry(2, 1, 99, 1), entry(3, 1, 11, 2)],
      [track(10), track(11)],
    );
    expect(views.single.items.map((i) => i.entryId), [1, 3]);
    expect(views.single.tracks.map((t) => t.id), [10, 11]);
  });

  test('keeps the same song twice and orders by position', () {
    final views = resolvePlaylists(
      [playlist(1)],
      [entry(1, 1, 10, 1), entry(2, 1, 11, 2), entry(3, 1, 10, 0)],
      [track(10), track(11)],
    );
    expect(views.single.items.map((i) => i.entryId), [3, 1, 2]);
  });

  test('orders newest first, ties by id descending', () {
    final views = resolvePlaylists(
      [
        playlist(1, createdAt: DateTime(2026, 11, 1)),
        playlist(2, createdAt: DateTime(2026, 11, 3)),
        playlist(3, createdAt: DateTime(2026, 11, 3)),
      ],
      const [],
      const [],
    );
    expect(views.map((v) => v.id), [3, 2, 1]);
  });

  test('meta counts songs and total time', () {
    final one = resolvePlaylists([playlist(1)], [entry(1, 1, 10, 0)], [
      track(10, durationMs: 240000),
    ]);
    expect(one.single.meta, '1 song · 4 min');
    expect(one.single.durationMs, 240000);

    final many = resolvePlaylists(
      [playlist(1)],
      [for (var i = 0; i < 18; i++) entry(i, 1, 10, i)],
      [track(10, durationMs: 223334)],
    );
    expect(many.single.meta, '18 songs · 1 h 7 min');
  });

  test('meta of an empty playlist', () {
    final v = resolvePlaylists([playlist(1)], const [], const []).single;
    expect(v.meta, '0 songs · 0 min');
  });

  test('mosaicCovers takes the first four distinct albums with a cover', () {
    final tracks = [
      track(1, album: 'A', artist: 'x', cover: 'a.jpg'),
      track(2, album: 'A', artist: 'x', cover: 'a.jpg'),
      track(3, album: 'B', artist: 'x', cover: 'b.jpg'),
      track(4, album: 'C', artist: 'x'),
      track(5, album: 'D', artist: 'x', cover: 'd.jpg'),
      track(6, album: 'E', artist: 'x', cover: 'e.jpg'),
      track(7, album: 'F', artist: 'x', cover: 'f.jpg'),
    ];
    final view = resolvePlaylists(
      [playlist(1)],
      [for (var i = 0; i < tracks.length; i++) entry(i, 1, tracks[i].id, i)],
      tracks,
    ).single;
    expect(view.mosaicCovers, ['a.jpg', 'b.jpg', 'd.jpg', 'e.jpg']);
  });

  test('mosaicCovers counts tracks without an album by their own cover', () {
    final tracks = [
      track(1, cover: 'x.jpg'),
      track(2, cover: 'x.jpg'),
      track(3, cover: 'y.jpg'),
      track(4),
    ];
    final view = resolvePlaylists(
      [playlist(1)],
      [for (var i = 0; i < tracks.length; i++) entry(i, 1, tracks[i].id, i)],
      tracks,
    ).single;
    expect(view.mosaicCovers, ['x.jpg', 'y.jpg']);
  });

  test('formatTotalDuration', () {
    expect(formatTotalDuration(0), '0 min');
    expect(formatTotalDuration(2640000), '44 min');
    expect(formatTotalDuration(3600000), '1 h 0 min');
    expect(formatTotalDuration(4020000), '1 h 7 min');
    expect(formatTotalDuration(59999), '0 min');
  });
}
