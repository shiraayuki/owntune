import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('owntune_storage_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('LibraryStorage.ensure creates audio and covers dirs', () async {
    final storage = LibraryStorage(Directory(p.join(tmp.path, 'library')));
    expect(storage.audioDir.existsSync(), isFalse);

    await storage.ensure();

    expect(storage.audioDir.existsSync(), isTrue);
    expect(storage.coversDir.existsSync(), isTrue);
    expect(storage.audioDir.path, p.join(tmp.path, 'library', 'audio'));
    expect(storage.coversDir.path, p.join(tmp.path, 'library', 'covers'));
  });

  test('file accessors resolve inside the matching directory', () {
    final storage = LibraryStorage(Directory(tmp.path));
    expect(storage.audioFile('a.mp3').path, p.join(tmp.path, 'audio', 'a.mp3'));
    expect(
      storage.coverFile('c.jpg').path,
      p.join(tmp.path, 'covers', 'c.jpg'),
    );
  });

  test('storeCover writes once and leaves no .part file', () async {
    final storage = LibraryStorage(Directory(p.join(tmp.path, 'library')));
    await storage.ensure();
    expect(await storage.storeCover('h.jpg', [1, 2, 3]), isTrue);
    expect(storage.coverFile('h.jpg').readAsBytesSync(), [1, 2, 3]);
    expect(await storage.storeCover('h.jpg', [9]), isFalse);
    expect(storage.coverFile('h.jpg').readAsBytesSync(), [1, 2, 3]);
    expect(storage.coversDir.listSync().map((f) => p.basename(f.path)), [
      'h.jpg',
    ]);
  });
}
