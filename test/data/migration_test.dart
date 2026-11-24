import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';

/// The schema of v0.2.0–v0.5.0 (schema version 1), as drift created it.
const _v1Schema = [
  'CREATE TABLE "tracks" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"file_name" TEXT NOT NULL UNIQUE, "original_name" TEXT NOT NULL, '
      '"content_hash" TEXT NOT NULL UNIQUE, "title" TEXT NULL, '
      '"artist" TEXT NULL, "album" TEXT NULL, "album_artist" TEXT NULL, '
      '"genre" TEXT NULL, "track_number" INTEGER NULL, '
      '"disc_number" INTEGER NULL, "year" INTEGER NULL, '
      '"duration_ms" INTEGER NOT NULL, "cover_file" TEXT NULL, '
      '"added_at" INTEGER NOT NULL, "play_count" INTEGER NOT NULL DEFAULT 0, '
      '"last_played_at" INTEGER NULL)',
  'CREATE TABLE "settings_entries" ("key" TEXT NOT NULL, '
      '"value" TEXT NOT NULL, PRIMARY KEY ("key"))',
  'INSERT INTO "tracks" ("file_name", "original_name", "content_hash", '
      '"title", "duration_ms", "added_at") '
      "VALUES ('h1.mp3', 'old.mp3', 'h1', 'Old Song', 1000, 0)",
  'PRAGMA user_version = 1',
];

/// The v1 schema plus what v0.6.0 added (schema version 2).
final _v2Schema = [
  ..._v1Schema.where((sql) => !sql.startsWith('PRAGMA')),
  'ALTER TABLE "tracks" ADD COLUMN "source_key" TEXT NULL',
  'CREATE UNIQUE INDEX "tracks_source_key" ON "tracks" ("source_key")',
  'PRAGMA user_version = 2',
];

TracksCompanion _row(String hash, String? sourceKey) => TracksCompanion.insert(
  fileName: '$hash.m4a',
  originalName: '$hash.m4a',
  contentHash: hash,
  durationMs: 1000,
  addedAt: DateTime(2026, 11, 20),
  sourceKey: Value(sourceKey),
);

void main() {
  test('v1 database gains source_key and keeps its rows', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          for (final sql in _v1Schema) {
            raw.execute(sql);
          }
        },
      ),
    );
    addTearDown(db.close);

    final rows = await db.select(db.tracks).get();
    expect(rows.single.title, 'Old Song');
    expect(rows.single.sourceKey, isNull);

    await db.into(db.tracks).insert(_row('h2', 'youtube:abc'));
    await db.into(db.tracks).insert(_row('h3', null));
    await expectLater(
      db.into(db.tracks).insert(_row('h4', 'youtube:abc')),
      throwsA(isA<Exception>()),
    );
  });

  test('v2 database gains playlist tables and keeps its rows', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          for (final sql in _v2Schema) {
            raw.execute(sql);
          }
        },
      ),
    );
    addTearDown(db.close);

    final track = (await db.select(db.tracks).get()).single;
    expect(track.title, 'Old Song');

    final playlistId = await db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(name: 'Mix', createdAt: DateTime(2026, 11)),
        );
    await db
        .into(db.playlistEntries)
        .insert(
          PlaylistEntriesCompanion.insert(
            playlistId: playlistId,
            trackId: track.id,
            position: 0,
          ),
        );

    final entry = (await db.select(db.playlistEntries).get()).single;
    expect(entry.trackId, track.id);
    expect((await db.select(db.playlists).get()).single.name, 'Mix');
  });
}
