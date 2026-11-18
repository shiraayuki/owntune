import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/core_status.dart';
import 'package:owntune/app/home_screen.dart';

void main() {
  testWidgets('zeigt App-Namen und Formate', (t) async {
    await t.pumpWidget(const OwntuneApp(status: CoreReady(['mp3', 'flac'])));
    expect(find.text('owntune'), findsOneWidget);
    expect(find.text('Rust-Kern: OK'), findsOneWidget);
    expect(find.text('mp3, flac'), findsOneWidget);
  });

  testWidgets('zeigt Fehlermeldung, wenn Rust nicht lädt', (t) async {
    await t.pumpWidget(const OwntuneApp(status: CoreFailed('lib fehlt')));
    expect(find.text('Rust-Kern: Fehler'), findsOneWidget);
    expect(find.textContaining('lib fehlt'), findsOneWidget);
  });
}
