import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/app/core_status.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real Rust core returns the M1 formats', (t) async {
    final s = await loadCoreStatus();
    expect(s, isA<CoreReady>());
    expect((s as CoreReady).formats, ['mp3', 'm4a', 'flac', 'ogg', 'wav']);
  });
}
