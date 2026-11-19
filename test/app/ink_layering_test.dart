import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';

/// Ink splashes are painted on the nearest [Material] ancestor, *below* that
/// Material's children. If a decorated background sits between that Material
/// and the tapped widget, the splash ends up hidden behind the background.
Finder _inkMaterial(Finder target) =>
    find.ancestor(of: target, matching: find.byType(Material)).first;

void main() {
  testWidgets('tab bar tap feedback is painted above the bar background', (
    t,
  ) async {
    await pumpApp(t);
    expect(
      find.ancestor(
        of: _inkMaterial(find.text('Albums')),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
  });

  final buttons = {
    'import': find.descendant(
      of: find.byKey(const Key('import-button')),
      matching: find.byIcon(CupertinoIcons.plus),
    ),
    'more': find.byIcon(CupertinoIcons.ellipsis),
  };
  for (final MapEntry(key: name, value: target) in buttons.entries) {
    testWidgets('$name button paints its feedback on its own circle', (
      t,
    ) async {
      await pumpApp(t);
      final material = t.widget<Material>(_inkMaterial(target));
      expect(material.shape, isA<CircleBorder>());
    });
  }
}
