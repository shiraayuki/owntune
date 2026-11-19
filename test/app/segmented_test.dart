import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/segmented.dart';
import 'package:owntune/app/theme.dart';

Future<List<int>> _pump(WidgetTester t, {int value = 0}) async {
  final picked = <int>[];
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light, const Color(0xffff7a59)),
      home: Scaffold(
        body: Segmented<int>(
          segments: const {0: 'One', 1: 'Two'},
          value: value,
          onChanged: picked.add,
        ),
      ),
    ),
  );
  return picked;
}

void main() {
  testWidgets('shows every label and reports taps', (t) async {
    final picked = await _pump(t);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    await t.tap(find.text('Two'));
    expect(picked, [1]);
  });

  testWidgets('marks the selected segment for accessibility', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, value: 1);
    expect(
      t.getSemantics(find.text('Two')),
      isSemantics(isSelected: true, isButton: true, hasSelectedState: true),
    );
    expect(
      t.getSemantics(find.text('One')),
      isSemantics(isSelected: false, isButton: true, hasSelectedState: true),
    );
    handle.dispose();
  });
}
