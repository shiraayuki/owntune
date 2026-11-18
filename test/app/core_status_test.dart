import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/core_status.dart';

void main() {
  test('loadCoreStatus liefert Formate, wenn Rust lädt', () async {
    final s = await loadCoreStatus(
      init: () async {},
      formats: () => ['mp3', 'flac'],
    );
    expect(s, isA<CoreReady>());
    expect((s as CoreReady).formats, ['mp3', 'flac']);
  });

  test(
    'loadCoreStatus liefert Fehler statt Absturz, wenn init wirft',
    () async {
      final s = await loadCoreStatus(
        init: () async => throw StateError('lib fehlt'),
        formats: () => [],
      );
      expect(s, isA<CoreFailed>());
      expect((s as CoreFailed).message, contains('lib fehlt'));
    },
  );

  test('loadCoreStatus liefert Fehler, wenn der Rust-Aufruf wirft', () async {
    final s = await loadCoreStatus(
      init: () async {},
      formats: () => throw Exception('panic'),
    );
    expect(s, isA<CoreFailed>());
  });
}
