import 'dart:io';
import 'dart:math';

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

  /// Stores [bytes] as the cover `covers/<name>`, written via
  /// `covers/<random>.part` so an interrupted write never leaves a truncated
  /// cover under its final name. Returns false, writing nothing, if the
  /// cover already exists.
  Future<bool> storeCover(String name, List<int> bytes) async {
    final target = coverFile(name);
    if (await target.exists()) return false;
    final tmp = coverFile('${_randomHex()}.part');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
    return true;
  }

  static final _random = Random.secure();

  static String _randomHex() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<void> ensure() async {
    await audioDir.create(recursive: true);
    await coversDir.create(recursive: true);
  }

  static Future<LibraryStorage> open() async {
    final support = await getApplicationSupportDirectory();
    return LibraryStorage(Directory(p.join(support.path, 'library')));
  }
}
