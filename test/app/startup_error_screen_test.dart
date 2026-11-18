import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/startup_error_screen.dart';

void main() {
  testWidgets('shows the error message when startup fails', (t) async {
    await t.pumpWidget(const StartupErrorApp(message: 'lib missing'));
    expect(find.text('owntune'), findsOneWidget);
    expect(find.text('Startup failed'), findsOneWidget);
    expect(find.text('lib missing'), findsOneWidget);
  });

  testWidgets('long error message fits on a small iPhone', (t) async {
    t.view.physicalSize = const Size(375, 667);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final message = 'Invalid argument(s): Failed to load dynamic library ' * 60;

    await t.pumpWidget(StartupErrorApp(message: message));

    expect(t.takeException(), isNull);
    final text = find.textContaining('Failed to load dynamic library');
    expect(text, findsOneWidget);
    expect(
      find
              .ancestor(of: text, matching: find.byType(SelectableText))
              .evaluate()
              .isNotEmpty ||
          t.widget(text) is SelectableText,
      isTrue,
    );
    expect(
      find.ancestor(of: text, matching: find.byType(SingleChildScrollView)),
      findsOneWidget,
    );
  });
}
