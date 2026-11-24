import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/home/for_you.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/player/queue_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AppDatabase db;
  late TrackRepository tracks;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('owntune_home_it');
    final storage = LibraryStorage(Directory('${tmp.path}/library'));
    await storage.ensure();
    db = AppDatabase(NativeDatabase(File('${tmp.path}/owntune.sqlite')));
    tracks = TrackRepository(db, storage);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('Home shows tiles and On Repeat after recorded plays', (t) async {
    final now = DateTime(2026, 11, 24, 12);
    for (var i = 1; i <= 5; i++) {
      await tracks.insert(
        TracksCompanion.insert(
          fileName: 'file$i.mp3',
          originalName: 'song$i.mp3',
          contentHash: 'hash$i',
          title: Value('Song $i'),
          artist: const Value('Artist A'),
          album: const Value('Album A'),
          trackNumber: Value(i),
          durationMs: 180000,
          addedAt: now.subtract(Duration(days: 10 - i)),
          // The play counter lives on the row; the song is played i times.
          playCount: Value(i <= 4 ? i : 0),
          lastPlayedAt: Value(
            i <= 4 ? now.subtract(const Duration(days: 1)) : null,
          ),
        ),
      );
    }
    final inserted = await tracks.watchAll().first;
    expect(inserted, hasLength(5));
    final albumKey = albumKeyOf(inserted.first)!;
    final sourceKey = '${albumKey.artist}\u0000${albumKey.title}';

    // Songs 1-4 are played from the album: song n is played n times.
    for (final track in inserted.take(4)) {
      for (var n = 0; n < track.id; n++) {
        await db
            .into(db.plays)
            .insert(
              PlaysCompanion.insert(
                trackId: track.id,
                startedAt: now.subtract(Duration(days: 1, hours: n)),
                listenedMs: 60000,
                counted: true,
                sourceKind: Value(QueueSourceKind.album.name),
                sourceKey: Value(sourceKey),
              ),
            );
      }
    }

    final repo = HomeRepository(db);
    final recent = await repo
        .watchRecentSources(since: now.subtract(const Duration(days: 365)))
        .first;
    final top = await repo
        .watchTopTracks(since: now.subtract(const Duration(days: 30)))
        .first;
    final forYou = buildForYou(
      library: Library.from(await tracks.watchAll().first),
      playlists: const [],
      liked: const [],
      recent: recent,
      topRecent: top,
      now: now,
    );

    expect(recent.map((r) => (r.kind, r.key)), [
      (QueueSourceKind.album, sourceKey),
    ]);
    expect(forYou.tiles, hasLength(1));
    expect(forYou.tiles.single, isA<AlbumTile>());
    expect((forYou.tiles.single as AlbumTile).album.title, 'Album A');

    expect(forYou.onRepeat, hasLength(4));
    expect(forYou.onRepeat.first.track.id, inserted[3].id);
    expect(forYou.onRepeat.first.subtitle, '4 plays');
    expect(forYou.onRepeat.last.subtitle, '1 play');
    // The fifth song was never played.
    expect(forYou.neverPlayed.map((c) => c.track.id), [inserted[4].id]);
  });
}
