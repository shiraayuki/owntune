import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';

final _songs = [
  track(1, title: 'Amber Lights', artist: 'Neon Harbor', album: 'Velvet Hours'),
  track(2, title: 'Backroads', artist: 'Kettle & Pine', album: 'Northbound'),
  track(3, title: 'Blue Hour', artist: 'The Quiet Coast', album: 'Low Tide'),
];

Future<void> _tab(WidgetTester t, String label) async {
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

Future<void> _filter(WidgetTester t, String label, String query) async {
  await t.enterText(find.widgetWithText(TextField, label), query);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('four tabs in order, starting on Library', (t) async {
    await pumpApp(t, songs: _songs);
    final bar = find.byType(BackdropFilter);
    double x(String l) =>
        t.getCenter(find.descendant(of: bar, matching: find.text(l))).dx;
    final labels = ['Home', 'Search', 'Library', 'Playlists'];
    for (var i = 1; i < labels.length; i++) {
      expect(x(labels[i - 1]), lessThan(x(labels[i])), reason: labels[i]);
    }
    expect(find.text('Library'), findsNWidgets(2)); // title and tab item
    expect(find.byIcon(CupertinoIcons.square_stack_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.house), findsOneWidget);
  });

  testWidgets('Home shows its placeholder without a search field', (t) async {
    await pumpApp(t, songs: _songs);
    await _tab(t, 'Home');
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Home arrives in a later version.'), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsNothing);
    expect(find.byIcon(CupertinoIcons.house_fill), findsOneWidget);
  });

  testWidgets('Library switches sub-tabs with the segmented control', (
    t,
  ) async {
    await pumpApp(t, songs: _songs);
    expect(find.widgetWithText(TextField, 'Search Songs'), findsOneWidget);
    await _tab(t, 'Albums');
    expect(
      find.widgetWithText(TextField, 'Search Albums').hitTestable(),
      findsOneWidget,
    );
    await _tab(t, 'Artists');
    expect(
      find.widgetWithText(TextField, 'Search Artists').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('each sub-tab keeps its query across sub-tabs and tabs', (
    t,
  ) async {
    await pumpApp(t, songs: _songs);
    await _filter(t, 'Search Songs', 'back');
    await _tab(t, 'Albums');
    await _tab(t, 'Songs');
    expect(find.text('Backroads'), findsOneWidget);
    expect(find.text('Blue Hour'), findsNothing);

    await _tab(t, 'Search');
    await _tab(t, 'Library');
    expect(find.text('Backroads').hitTestable(), findsOneWidget);
    expect(find.text('Blue Hour'), findsNothing);
  });

  testWidgets('empty library: no sub-tabs, import still offered', (t) async {
    await pumpApp(t);
    expect(find.byKey(const ValueKey('library-segments')), findsNothing);
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('Playlists shows its empty state without a search field', (
    t,
  ) async {
    await pumpApp(t, songs: _songs);
    await _tab(t, 'Playlists');
    expect(find.text('No playlists yet'), findsOneWidget);
    expect(
      find.text('Creating playlists arrives in a later version.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the Search tab searches everything, tab bar visible', (t) async {
    await pumpApp(t, songs: _songs);
    await _tab(t, 'Search');
    await t.enterText(find.byType(TextField), 'neon');
    await t.pumpAndSettle();
    expect(find.text('Album · Neon Harbor'), findsOneWidget);
    expect(find.text('Song · Neon Harbor'), findsOneWidget);
    expect(find.text('Playlists').hitTestable(), findsOneWidget);
  });

  testWidgets('Songs filters inline and Cancel restores the list', (t) async {
    await pumpApp(t, songs: _songs);
    await _filter(t, 'Search Songs', 'back');
    expect(find.text('Backroads'), findsOneWidget);
    expect(find.text('Blue Hour'), findsNothing);
    expect(find.byKey(const ValueKey('section-B')), findsNothing);
    expect(find.text('3 songs · sorted by title'), findsNothing);

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Blue Hour'), findsOneWidget);
    expect(find.text('3 songs · sorted by title'), findsOneWidget);
  });

  testWidgets('Albums filter by album artist, Artists by name', (t) async {
    await pumpApp(t, songs: _songs);
    await _tab(t, 'Albums');
    await _filter(t, 'Search Albums', 'quiet');
    expect(find.text('Low Tide'), findsOneWidget);
    expect(find.text('Velvet Hours'), findsNothing);

    await _tab(t, 'Artists');
    await _filter(t, 'Search Artists', 'kettle');
    expect(find.text('Kettle & Pine'), findsOneWidget);
    expect(find.text('Neon Harbor'), findsNothing);
    await _filter(t, 'Search Artists', 'zzz');
    expect(find.text('No results for "zzz"'), findsOneWidget);
  });

  testWidgets('+ menu: New Playlist is disabled', (t) async {
    final picker = FakePicker();
    await pumpApp(t, songs: _songs, picker: picker);
    await t.tap(find.byKey(const Key('import-button')));
    await t.pumpAndSettle();
    for (final label in ['New Playlist']) {
      final item = t.widget<PopupMenuItem<Object>>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(PopupMenuItem<Object>),
        ),
      );
      expect(item.enabled, isFalse, reason: label);
    }
    await t.tap(find.byKey(const Key('menu-import')));
    await t.pumpAndSettle();
    expect(picker.picks, 1);
  });
}
