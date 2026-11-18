import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/core_status.dart';
import 'package:owntune/app/home_screen.dart';

void main() {
  testWidgets('shows app name and formats', (t) async {
    await t.pumpWidget(const OwntuneApp(status: CoreReady(['mp3', 'flac'])));
    expect(find.text('owntune'), findsOneWidget);
    expect(find.text('Rust core: OK'), findsOneWidget);
    expect(find.text('mp3, flac'), findsOneWidget);
  });

  testWidgets('long error message fits on a small iPhone', (t) async {
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

  testWidgets('shows the error message when Rust fails to load', (t) async {
    await t.pumpWidget(const OwntuneApp(status: CoreFailed('lib missing')));
    expect(find.text('Rust core: error'), findsOneWidget);
    expect(find.textContaining('lib missing'), findsOneWidget);
  });
}
