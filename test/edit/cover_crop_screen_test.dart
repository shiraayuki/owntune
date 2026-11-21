import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/edit/cover_crop_screen.dart';
import 'package:owntune/edit/cover_image.dart';

UprightCover _cover() {
  final image = img.Image(width: 200, height: 100);
  img.fill(image, color: img.ColorRgb8(10, 120, 200));
  return uprightCover(img.encodePng(image))!;
}

/// Pumps a button that opens the crop page and returns where its result
/// lands.
Future<List<Rect?>> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final results = <Rect?>[];
  final cover = _cover();
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, const Color(0xffff7a59)),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              results.add(await openCoverCrop(context, cover)),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('shows title, hint and both buttons', (t) async {
    await _pump(t);
    expect(find.text('Move and Scale'), findsOneWidget);
    expect(find.text('Pinch to zoom · drag to move'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
  });

  testWidgets('Choose without gestures returns the centred square', (t) async {
    final results = await _pump(t);
    await t.tap(find.text('Choose'));
    await t.pumpAndSettle();
    expect(results, [const Rect.fromLTWH(50, 0, 100, 100)]);
  });

  testWidgets('Cancel returns null', (t) async {
    final results = await _pump(t);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(results, [null]);
  });

  testWidgets('dragging moves the crop', (t) async {
    final results = await _pump(t);
    await t.drag(find.byType(InteractiveViewer), const Offset(100, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose'));
    await t.pumpAndSettle();
    final rect = results.single!;
    expect(rect.left, lessThan(50));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.width, closeTo(100, 0.001));
  });
}
