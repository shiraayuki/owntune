import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/core_status.dart';

void main() {
  test('loadCoreStatus returns the formats when Rust loads', () async {
    final s = await loadCoreStatus(
      init: () async {},
      formats: () => ['mp3', 'flac'],
    );
    expect(s, isA<CoreReady>());
    expect((s as CoreReady).formats, ['mp3', 'flac']);
  });

  test(
    'loadCoreStatus returns an error instead of crashing when init throws',
    () async {
      final s = await loadCoreStatus(
        init: () async => throw StateError('lib missing'),
        formats: () => [],
      );
      expect(s, isA<CoreFailed>());
      expect((s as CoreFailed).message, contains('lib missing'));
    },
  );

  test('loadCoreStatus returns an error when the Rust call throws', () async {
    final s = await loadCoreStatus(
      init: () async {},
      formats: () => throw Exception('panic'),
    );
    expect(s, isA<CoreFailed>());
    expect((s as CoreFailed).message, contains('panic'));
  });
}
