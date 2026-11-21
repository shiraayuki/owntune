import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/edit/cover_image.dart';
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

  testWidgets('a cover set on two songs is in both files, then removed', (
    t,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('owntune_cover_it');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final picked = [
      for (final name in ['tagged.mp3', 'tagged.m4a'])
        File('${fixturesDir().path}/$name').copySync('${tmp.path}/$name').path,
    ];
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
    ).importFiles(picked);
    final before = await repo.watchAll().first;
    expect(before, hasLength(2));
    final oldCovers = {for (final t in before) t.coverFile}..remove(null);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        storageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    final saver = container.read(tagSaverProvider);

    final image = img.Image(width: 300, height: 200);
    img.fill(image, color: img.ColorRgb8(20, 160, 90));
    final upright = uprightCover(img.encodePng(image))!;
    final Uint8List data = cropCover(
      upright.bytes,
      const Rect.fromLTWH(50, 0, 200, 200),
    );
    final hash = hashBytes(data: data);

    expect(
      await saver.save(
        before,
        TagEdit(const {}, cover: CoverSet(data, 'image/jpeg')),
      ),
      isEmpty,
    );
    final withCover = await repo.watchAll().first;
    for (final (i, t) in withCover.indexed) {
      final read = (await readTrack(path: storage.audioFile(t.fileName).path))
          .track!;
      expect(read.cover!.hash, hash);
      expect(t.coverFile, '$hash.jpg');
      expect(t.contentHash, before[i].contentHash);
      expect(t.fileName, before[i].fileName);
    }
    expect(storage.coverFile('$hash.jpg').existsSync(), isTrue);
    for (final old in oldCovers) {
      expect(storage.coverFile(old!).existsSync(), isFalse, reason: old);
    }

    expect(
      await saver.save(withCover, const TagEdit({}, cover: CoverRemove())),
      isEmpty,
    );
    final removed = await repo.watchAll().first;
    for (final t in removed) {
      final read = (await readTrack(path: storage.audioFile(t.fileName).path))
          .track!;
      expect(read.cover, isNull);
      expect(t.coverFile, isNull);
    }
    expect(storage.coverFile('$hash.jpg').existsSync(), isFalse);
  });
}
