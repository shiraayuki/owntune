import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/library/section_index.dart';

import '../support/fakes.dart';

void main() {
  // iOS "xxxLarge", the largest size before the accessibility sizes.
  const scale = 1.35;

  final many = [
    for (final (i, l) in ['A', 'B', 'C', 'D', 'E', 'F'].indexed)
      for (var n = 0; n < 6; n++)
        track(
          i * 10 + n,
          title: '$l song $n',
          artist: 'Artist',
          album: 'Album $l',
        ),
  ];

  testWidgets('songs rows grow with the text size and the index still jumps', (
    t,
  ) async {
    // iPhone 14: the 800×600 default leaves too little room for the full
    // A–Z strip under the sub-tabs and above the tab bar.
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(t, songs: many);
    expect(t.takeException(), isNull);

    await t.tap(
      find.descendant(of: find.byType(SectionIndex), matching: find.text('D')),
    );
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(find.byKey(const ValueKey('section-D'))).dy,
      t.getTopLeft(find.byType(ListView)).dy,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('album cards grow with the text size', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(t, songs: many);
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('library sub-tabs fit at large text', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(t, songs: many);
    expect(t.takeException(), isNull);
    for (final sub in ['Artists', 'Songs']) {
      await t.tap(find.text(sub));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: sub);
    }
  });
}
