import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/queue_source.dart';

import '../support/fakes.dart';

final _noon = clockProvider.overrideWithValue(() => DateTime(2026, 11, 24, 12));

Future<void> _tall(WidgetTester t) async {
  t.view.physicalSize = const Size(2000, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

PlayerState _state(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(OwntuneApp)))
        .read(playerProvider);

Track _song(int id, String title, {String? album}) =>
    track(id, title: title, artist: 'Juno Vale', album: album);

Finder _navBack(String label) =>
    find.descendant(of: find.byType(NavRow), matching: find.text(label));

void main() {
  testWidgets('header opens the full On Repeat list with up to 50 songs', (
    t,
  ) async {
    await _tall(t);
    final songs = [for (var i = 1; i <= 60; i++) _song(i, 'Song $i')];
    final home = FakeHomeRepository()
      ..top = [for (var i = 1; i <= 60; i++) TrackPlayCount(i, 100 - i)];
    await pumpApp(t, songs: songs, home: home, overrides: [_noon]);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('home-header-on-repeat')));
    await t.pumpAndSettle();

    expect(_navBack('Home'), findsOneWidget);
    expect(find.text('On Repeat'), findsOneWidget);
    // The row is gone from the visible tree behind the pushed page, so every
    // SongRow belongs to the list; the list is lazy, so scroll to the end.
    expect(find.text('99 plays'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Song 50'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('50 plays'), findsOneWidget);
    expect(find.text('Song 51'), findsNothing);
    expect(find.byKey(const Key('home-list-song-50')), findsOneWidget);
    expect(find.byKey(const Key('home-list-song-51')), findsNothing);
  });

  testWidgets('tapping a song in the list plays the list from it with the '
      'other source', (t) async {
    await _tall(t);
    final songs = [for (var i = 1; i <= 15; i++) _song(i, 'Song $i')];
    final home = FakeHomeRepository()
      ..top = [for (var i = 1; i <= 15; i++) TrackPlayCount(i, 100 - i)];
    final engine = FakeAudioEngine();
    await pumpApp(
      t,
      songs: songs,
      home: home,
      engine: engine,
      overrides: [_noon],
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('home-header-on-repeat')));
    await t.pumpAndSettle();
    // Past the ten cards of the row: the full list is queued.
    await t.tap(find.byKey(const Key('home-list-song-12')));
    await t.pumpAndSettle();

    expect(engine.loaded, ['hash12.mp3']);
    final state = _state(t);
    expect(
      [for (final e in state.queue.entries) e.trackId],
      [for (var i = 1; i <= 15; i++) i],
    );
    expect(state.queue.index, 11);
    expect(
      state.queue.source,
      const QueueSource(QueueSourceKind.other, 'On Repeat'),
    );
  });

  testWidgets('Recently Added list shows albums and opens one', (t) async {
    await _tall(t);
    await pumpApp(
      t,
      songs: [
        _song(1, 'Amber Lights', album: 'Dusk'),
        _song(2, 'Backroads', album: 'Dawn'),
      ],
      overrides: [_noon],
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('home-header-recently-added')));
    await t.pumpAndSettle();

    expect(_navBack('Home'), findsOneWidget);
    expect(find.text('Recently Added'), findsOneWidget);
    expect(find.byKey(const Key('home-list-album-0')), findsOneWidget);
    expect(find.byKey(const Key('home-list-album-1')), findsOneWidget);
    expect(find.text('Dusk'), findsOneWidget);
    expect(find.text('Juno Vale'), findsNWidgets(2));

    await t.tap(find.text('Dusk'));
    await t.pumpAndSettle();
    expect(find.text('Amber Lights'), findsOneWidget);
    expect(_navBack('Recently Added'), findsOneWidget);
  });

  testWidgets('a failing library shows the load error instead of an empty '
      'page', (t) async {
    await _tall(t);
    final songs = StreamController<List<Track>>();
    addTearDown(songs.close);
    final home = FakeHomeRepository()
      ..top = [for (var i = 1; i <= 5; i++) TrackPlayCount(i, 10 - i)];
    await pumpApp(t, songsStream: songs.stream, home: home, overrides: [_noon]);
    songs.add([for (var i = 1; i <= 5; i++) _song(i, 'Song $i')]);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-header-on-repeat')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('home-list-song-1')), findsOneWidget);

    songs.addError(StateError('database is locked'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('home-list-song-1')), findsNothing);
    expect(find.text('Could not load Home'), findsWidgets);
    expect(find.textContaining('database is locked'), findsWidgets);
  });
}
