import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/text_tabs.dart';
import 'package:owntune/app/theme.dart';

Future<List<int>> _pump(WidgetTester t, {int value = 0}) async {
  final picked = <int>[];
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light, const Color(0xffff7a59)),
      home: Scaffold(
        body: TextTabs<int>(
          segments: const {0: 'Songs', 1: 'Albums', 2: 'Artists'},
          value: value,
          onChanged: picked.add,
        ),
      ),
    ),
  );
  return picked;
}

OwntuneColors _colors(WidgetTester t) =>
    Theme.of(t.element(find.byType(TextTabs<int>))).extension<OwntuneColors>()!;

void main() {
  testWidgets('shows all labels and reports taps', (t) async {
    final picked = await _pump(t);
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    await t.tap(find.text('Albums'));
    expect(picked, [1]);
  });

  testWidgets('selected label uses the text color, others muted', (t) async {
    await _pump(t);
    final c = _colors(t);
    expect(t.widget<Text>(find.text('Songs')).style!.color, c.text);
    expect(t.widget<Text>(find.text('Albums')).style!.color, c.muted);
  });

  testWidgets('marks the selected tab for semantics', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t);
    expect(
      t.getSemantics(find.text('Songs')),
      isSemantics(isSelected: true, isButton: true, hasSelectedState: true),
    );
    expect(
      t.getSemantics(find.text('Albums')),
      isSemantics(isSelected: false, isButton: true, hasSelectedState: true),
    );
    handle.dispose();
  });

  testWidgets('draws the accent bar only under the selected label', (t) async {
    await _pump(t, value: 1);
    final bar = find.byKey(const Key('text-tab-bar'));
    expect(bar, findsOneWidget);
    expect(t.getSize(bar).width, t.getSize(find.text('Albums')).width);
    expect(t.getSize(bar).height, 3);
    expect(t.getTopLeft(bar).dx, t.getTopLeft(find.text('Albums')).dx);
    final box = t.widget<Container>(bar).decoration! as BoxDecoration;
    expect(box.color, _colors(t).accent);
  });
}
