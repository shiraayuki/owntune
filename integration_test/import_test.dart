import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/src/rust/api/library.dart';
import 'package:owntune/src/rust/api/metadata.dart';
import 'package:owntune/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('imports the fixture set with the real Rust reader', (t) async {
    final fixtures = Directory('${Directory.current.path}/test/fixtures/audio');
    expect(fixtures.existsSync(), isTrue, reason: 'missing ${fixtures.path}');

    final tmp = Directory.systemTemp.createTempSync('owntune_import_it');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final picked = Directory('${tmp.path}/picked')..createSync();
    for (final name in [
      'tagged.mp3',
      'tagged.flac',
      'tagged.m4a',
      'demo_3.wav',
      'unicode.mp3',
      'evening-walk.ogg',
      'broken.mp3',
    ]) {
      File('${fixtures.path}/$name').copySync('${picked.path}/$name');
    }
    File('${fixtures.path}/tagged.mp3').copySync('${picked.path}/copy.mp3');

    final storage = LibraryStorage(Directory('${tmp.path}/library'));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TrackRepository(db, storage);
    final importer = Importer(
      repo: repo,
      storage: storage,
      read: (p) => readTrack(path: p),
      supportedExtensions: supportedFormats().toSet(),
    );

    final names = [
      'tagged.mp3',
      'tagged.flac',
      'tagged.m4a',
      'demo_3.wav',
      'unicode.mp3',
      'copy.mp3', // same bytes as tagged.mp3
      'evening-walk.ogg',
      'broken.mp3',
    ];
    final summary = await importer.importFiles([
      for (final n in names) '${picked.path}/$n',
    ]);

    expect(summary.added, 5);
    expect(summary.duplicates, 1);
    expect(summary.unsupported, ['evening-walk.ogg', 'broken.mp3']);
    expect(summary.checked, 8);
    expect(await repo.count(), 5);

    final rows = await repo.watchAll().first;
    final byName = {for (final r in rows) r.originalName: r};
    expect(byName['tagged.mp3']!.title, 'After the Rain');
    expect(byName['tagged.mp3']!.coverFile, endsWith('.png'));
    expect(byName['tagged.flac']!.coverFile, endsWith('.jpg'));
    expect(byName['tagged.m4a']!.coverFile, isNull);
    for (final r in rows) {
      expect(storage.audioFile(r.fileName).existsSync(), isTrue);
    }
    expect(
      storage.audioDir.listSync().any((e) => e.path.contains('.part')),
      isFalse,
    );
  });
}
