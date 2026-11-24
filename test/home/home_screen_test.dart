import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/library/navigation.dart';

import '../support/fakes.dart';

final _evening = clockProvider.overrideWithValue(
  () => DateTime(2026, 11, 24, 20),
);

void main() {
  testWidgets('the app opens on Home with the greeting', (t) async {
    await pumpApp(t, songs: [track(1)], overrides: [_evening]);
    expect(find.text('Good evening'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.house_fill), findsOneWidget);
    expect(find.byKey(const Key('home-segments')), findsOneWidget);
  });

  testWidgets('the greeting follows the clock', (t) async {
    await pumpApp(
      t,
      songs: [track(1)],
      overrides: [
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 24, 8)),
      ],
    );
    expect(find.text('Good morning'), findsOneWidget);
  });

  testWidgets('sub-tabs switch to the Stats placeholder', (t) async {
    await pumpApp(t, songs: [track(1)], overrides: [_evening]);
    expect(find.byKey(const Key('stats-placeholder')), findsNothing);
    await t.tap(find.text('Stats'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('stats-placeholder')), findsOneWidget);
    expect(find.text('Stats are coming'), findsOneWidget);
    expect(
      find.text(
        'Listening time, top artists and more arrive in the next version.',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('For You'));
    await t.pumpAndSettle();
    expect(find.text('Stats are coming'), findsNothing);
  });

  testWidgets('empty library shows Import Music and Search Online', (t) async {
    final picker = FakePicker();
    await pumpApp(t, picker: picker, overrides: [_evening]);
    expect(find.byKey(const Key('for-you-empty')), findsOneWidget);
    expect(find.text('Your music lives here'), findsOneWidget);
    expect(
      find.text('Import files you already have, or find songs on YouTube.'),
      findsOneWidget,
    );
    // The sub-tabs stay visible, unlike on Library.
    expect(find.byKey(const Key('home-segments')), findsOneWidget);

    await t.tap(
      find.descendant(
        of: find.byKey(const Key('for-you-empty')),
        matching: find.text('Import Music'),
      ),
    );
    await t.pumpAndSettle();
    expect(picker.picks, 1);
  });

  testWidgets('Search Online from the empty state has the back label Home', (
    t,
  ) async {
    await pumpApp(t, overrides: [_evening]);
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('for-you-empty')),
        matching: find.text('Search Online'),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(NavRow), matching: find.text('Home')),
      findsOneWidget,
    );
  });

  testWidgets('"+" → Search Online on Home has the back label Home, not the '
      'greeting', (t) async {
    await pumpApp(t, songs: [track(1)], overrides: [_evening]);
    await t.tap(find.byKey(const Key('import-button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-search-online')));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(NavRow), matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NavRow),
        matching: find.text('Good evening'),
      ),
      findsNothing,
    );
  });

  testWidgets('a failing library load shows Could not load Home', (t) async {
    await pumpApp(
      t,
      songsStream: Stream.error(StateError('disk I/O error')),
      overrides: [_evening],
    );
    expect(find.text('Could not load Home'), findsOneWidget);
    expect(find.textContaining('disk I/O error'), findsOneWidget);
  });
}
