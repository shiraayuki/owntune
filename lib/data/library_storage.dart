import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Locations of the app-owned library: `<root>/audio` and `<root>/covers`.
///
/// The database stores file names only; this class resolves them to paths.
class LibraryStorage {
  LibraryStorage(this.root);

  final Directory root;

  Directory get audioDir => Directory(p.join(root.path, 'audio'));
  Directory get coversDir => Directory(p.join(root.path, 'covers'));

  File audioFile(String fileName) => File(p.join(audioDir.path, fileName));
  File coverFile(String fileName) => File(p.join(coversDir.path, fileName));

  Future<void> ensure() async {
    await audioDir.create(recursive: true);
    await coversDir.create(recursive: true);
  }

  static Future<LibraryStorage> open() async {
    final support = await getApplicationSupportDirectory();
    return LibraryStorage(Directory(p.join(support.path, 'library')));
  }
}
