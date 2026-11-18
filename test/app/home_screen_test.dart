import 'package:material_ui/material_ui.dart';
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

  testWidgets('lange Fehlermeldung passt auf ein kleines iPhone', (t) async {
    t.view.physicalSize = const Size(375, 667);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final message = 'Invalid argument(s): Failed to load dynamic library ' * 60;

    await t.pumpWidget(OwntuneApp(status: CoreFailed(message)));

    expect(t.takeException(), isNull);
    expect(
      find.textContaining('Failed to load dynamic library'),
      findsOneWidget,
    );
  });

  testWidgets('zeigt Fehlermeldung, wenn Rust nicht lädt', (t) async {
    await t.pumpWidget(const OwntuneApp(status: CoreFailed('lib fehlt')));
    expect(find.text('Rust-Kern: Fehler'), findsOneWidget);
    expect(find.textContaining('lib fehlt'), findsOneWidget);
  });
}
