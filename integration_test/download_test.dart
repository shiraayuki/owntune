import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/edit/track_tags.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/src/rust/api/library.dart';
import 'package:owntune/src/rust/api/metadata.dart';
import 'package:owntune/src/rust/frb_generated.dart';

import 'support/fixtures.dart';

/// The download pipeline after the network part, with the real Rust core:
/// a YouTube-like DASH M4A gets tags and cover and is imported with its
/// source key.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('a downloaded DASH M4A is tagged and imported', (t) async {
    final tmp = Directory.systemTemp.createTempSync('owntune_download_it');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final part = File('${fixturesDir().path}/dash.m4a')
        .copySync('${tmp.path}/audio.part.m4a');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cover = img.encodeJpg(img.Image(width: 32, height: 32));
    final error = await container.read(downloadTagWriterProvider)(
      part.path,
      const TrackTags(title: 'Numb', artist: 'Linkin Park', album: 'Meteora'),
      (data: cover, mime: 'image/jpeg'),
    );
    expect(error, isNull);
    final named = part.renameSync('${tmp.path}/Linkin Park - Numb.m4a');

    final storage = LibraryStorage(Directory('${tmp.path}/library'));
    await storage.ensure();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TrackRepository(db, storage);
    final summary = await Importer(
      repo: repo,
      storage: storage,
      read: (p) => readTrack(path: p),
      supportedExtensions: supportedFormats().toSet(),
    ).importFiles([named.path], sourceKeys: {named.path: 'youtube:abc'});
    expect(summary.added, 1, reason: '${summary.failures}');

    final row = (await repo.watchAll().first).single;
    expect(row.title, 'Numb');
    expect(row.artist, 'Linkin Park');
    expect(row.album, 'Meteora');
    expect(row.sourceKey, 'youtube:abc');
    expect(row.originalName, 'Linkin Park - Numb.m4a');
    expect(row.coverFile, isNotNull);
    expect(storage.coverFile(row.coverFile!).existsSync(), isTrue);
    final read = (await readTrack(path: storage.audioFile(row.fileName).path))
        .track!;
    expect(read.durationMs, closeTo(1128, 50));
  });
}
