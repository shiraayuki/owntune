import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points every path_provider directory at its own temp folder.
class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.root);

  final Directory root;

  String _dir(String name) =>
      (Directory('${root.path}/$name')..createSync()).path;

  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');

  @override
  Future<String?> getTemporaryPath() async => _dir('tmp');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'AppDatabase.open stores the database under Application Support',
    () async {
      final root = Directory.systemTemp.createTempSync('owntune_db_location');
      addTearDown(() => root.deleteSync(recursive: true));
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePaths(root);
      addTearDown(() => PathProviderPlatform.instance = previous);

      final db = AppDatabase.open();
      await db.select(db.settingsEntries).get();
      await db.close();

      expect(File('${root.path}/support/owntune.sqlite').existsSync(), isTrue);
      final documents = Directory('${root.path}/documents');
      expect(
        documents.existsSync() && documents.listSync().isNotEmpty,
        isFalse,
        reason: 'nothing may be written to Documents',
      );
      // Kept apart from the library folder that cleanupOrphans scans.
      expect(Directory('${root.path}/support/library').existsSync(), isFalse);
    },
  );
}
