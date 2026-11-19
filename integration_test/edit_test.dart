import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('edits a fixture with the real Rust core', (t) async {
    final tmp = Directory.systemTemp.createTempSync('owntune_edit_it');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final picked = File('${fixturesDir().path}/tagged.mp3')
        .copySync('${tmp.path}/tagged.mp3');

    final storage = LibraryStorage(Directory('${tmp.path}/library'));
    await storage.ensure();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TrackRepository(db, storage);
    await Importer(
      repo: repo,
      storage: storage,
      read: (p) => readTrack(path: p),
      supportedExtensions: supportedFormats().toSet(),
    ).importFiles([picked.path]);
    final before = (await repo.watchAll().first).single;

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        storageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    final failures = await container.read(tagSaverProvider).save([
      before,
    ], const TagEdit({TagField.title: 'After the Storm', TagField.year: ''}));
    expect(failures, isEmpty);

    final file = storage.audioFile(before.fileName);
    final read = (await readTrack(path: file.path)).track!;
    expect(read.title, 'After the Storm');
    expect(read.year, isNull);
    expect(read.artist, 'Juno Vale');

    final after = (await repo.watchAll().first).single;
    expect(after.title, 'After the Storm');
    expect(after.year, isNull);
    expect(after.contentHash, before.contentHash);
    expect(after.fileName, before.fileName);
    expect(read.contentHash, isNot(before.contentHash));
    expect(storage.audioDir.listSync().map((e) => e.uri.pathSegments.last), [
      before.fileName,
    ]);
  });
}
