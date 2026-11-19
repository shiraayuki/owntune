import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/search_screen.dart';

import '../support/fakes.dart';

final _songs = [
  track(1, title: 'Amber Lights', artist: 'Neon Harbor', album: 'Velvet Hours'),
  track(2, title: 'Static', artist: 'Neon Harbor', album: 'Midnight Static'),
  track(3, title: 'Backroads', artist: 'Kettle & Pine', album: 'Northbound'),
];

Future<void> _openSearch(
  WidgetTester t, [
  String label = 'Search Songs',
]) async {
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

Future<void> _type(WidgetTester t, String query) async {
  await t.enterText(find.byType(TextField), query);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('every tab has a search field that opens the search', (t) async {
    await pumpApp(t, songs: _songs);
    for (final (tab, label) in [
      ('Songs', 'Search Songs'),
      ('Albums', 'Search Albums'),
      ('Artists', 'Search Artists'),
    ]) {
      await t.tap(find.text(tab).last);
      await t.pumpAndSettle();
      await _openSearch(t, label);
      expect(find.byType(SearchScreen), findsOneWidget, reason: tab);
      // The query field has focus, so the keyboard is up.
      expect(t.testTextInput.hasAnyClients, isTrue, reason: tab);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.byType(SearchScreen), findsNothing, reason: tab);
    }
  });

  testWidgets('results are grouped: artists, albums, songs', (t) async {
    await pumpApp(t, songs: _songs);
    await _openSearch(t);
    await _type(t, 'neon');

    final order = [
      'Artists',
      'Neon Harbor',
      'Albums',
      'Midnight Static',
      'Velvet Hours',
      'Songs',
      'Amber Lights',
      'Static',
    ];
    for (var i = 0; i + 1 < order.length; i++) {
      expect(
        t.getTopLeft(find.text(order[i])).dy,
        lessThan(t.getTopLeft(find.text(order[i + 1])).dy),
        reason: '${order[i]} before ${order[i + 1]}',
      );
    }
    expect(find.text('Artist'), findsOneWidget);
    expect(find.text('Album · Neon Harbor'), findsNWidgets(2));
    expect(find.text('Song · Neon Harbor'), findsNWidgets(2));
    expect(find.text('Backroads'), findsNothing);
  });

  testWidgets('no matches show a message, an empty query nothing', (t) async {
    await pumpApp(t, songs: _songs);
    await _openSearch(t);
    expect(find.textContaining('No results'), findsNothing);
    await _type(t, 'zzz');
    expect(find.text('No results for "zzz"'), findsOneWidget);
  });

  testWidgets('the clear button empties the query', (t) async {
    await pumpApp(t, songs: _songs);
    await _openSearch(t);
    await _type(t, 'neon');
    await t.tap(find.byKey(const Key('search-clear')));
    await t.pumpAndSettle();
    expect(find.text('Neon Harbor'), findsNothing);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });

  testWidgets('an album opens with back label Search and back returns', (
    t,
  ) async {
    await pumpApp(t, songs: _songs);
    await _openSearch(t);
    await _type(t, 'neon');
    await t.tap(find.text('Velvet Hours'));
    await t.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(NavRow), matching: find.text('Search')),
      findsOneWidget,
    );

    await tapBack(t);
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('Velvet Hours'), findsOneWidget);
  });

  testWidgets('results refresh when the library changes', (t) async {
    final tracks = StreamController<List<Track>>();
    addTearDown(tracks.close);
    tracks.add(_songs);
    await pumpApp(t, songsStream: tracks.stream);
    await _openSearch(t);
    await _type(t, 'neon');
    expect(find.text('Neon Swimmers'), findsNothing);

    tracks.add([
      ..._songs,
      track(9, title: 'Neon Swimmers', artist: 'Lumen Kids'),
    ]);
    await t.pumpAndSettle();
    expect(find.text('Neon Swimmers'), findsOneWidget);
    expect(find.text('Song · Lumen Kids'), findsOneWidget);
  });
}
