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
}
