import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/player/cover_tint.dart';

void main() {
  test('a missing cover file gives no tint', () async {
    final dir = Directory.systemTemp.createTempSync('owntune_tint');
    addTearDown(() => dir.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [storageProvider.overrideWithValue(LibraryStorage(dir))],
    );
    addTearDown(container.dispose);
    expect(
      await container.read(coverColorsProvider('gone.jpg').future),
      isNull,
    );
  });
}
