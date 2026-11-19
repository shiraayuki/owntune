import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/library/search_screen.dart';

import '../support/fakes.dart';

Future<FakeImporter> _startHiddenImport(WidgetTester t) async {
  final importer = FakeImporter();
  await pumpApp(t, importer: importer, picker: FakePicker(['/a/one.mp3']));
  await tapImport(t);
  await t.tap(find.text('Hide – keep importing'));
  await t.pumpAndSettle();
  return importer;
}

void main() {
  testWidgets('the failure text in the import sheet can be selected', (
    t,
  ) async {
    final importer = await _startHiddenImport(t);
    importer.fail(Exception('disk full'));
    await t.pumpAndSettle();

    await t.longPress(find.textContaining('disk full'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('an import sheet stays above the keyboard', (t) async {
    // iPhone 14 size; the keyboard covers the lower 336pt.
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final importer = await _startHiddenImport(t);
    await t.tap(find.text('Search').last);
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byType(SearchTab),
        matching: find.byType(TextField),
      ),
    );
    await t.pumpAndSettle();

    t.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();

    importer.finish(summary47);
    await t.pumpAndSettle();
    final screenHeight = t.view.physicalSize.height / t.view.devicePixelRatio;
    expect(
      t.getBottomLeft(find.text('Done')).dy,
      lessThanOrEqualTo(screenHeight - 336),
    );
  });
}
