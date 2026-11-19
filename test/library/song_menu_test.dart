import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/artist_screen.dart';
import 'package:owntune/library/navigation.dart';

import '../support/fakes.dart';

void main() {
  final songs = [
    track(
      1,
      title: 'Amber Lights',
      artist: 'Neon Harbor',
      album: 'Velvet Hours',
      trackNumber: 1,
    ),
    track(2, title: 'Loose Song'),
  ];

  Future<void> longPress(WidgetTester t, String title) async {
    await t.longPress(find.text(title));
    await t.pumpAndSettle();
  }

  Finder backLabel(String label) =>
      find.descendant(of: find.byType(NavRow), matching: find.text(label));

  testWidgets('Go to Album from Library › Songs shows back label Library', (
    t,
  ) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await longPress(t, 'Amber Lights');
    expect(find.text('Go to Album'), findsOneWidget);
    expect(find.text('Go to Artist'), findsOneWidget);
    expect(find.text('Delete from Library'), findsOneWidget);

    await t.tap(find.text('Go to Album'));
    await t.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(backLabel('Library'), findsOneWidget);
  });

  testWidgets('Go to Album is missing for a track without album', (t) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await longPress(t, 'Loose Song');
    expect(find.text('Go to Album'), findsNothing);
    expect(find.text('Go to Artist'), findsOneWidget);
  });

  testWidgets('Go to Artist opens Unknown Artist for an untagged track', (
    t,
  ) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await longPress(t, 'Loose Song');
    await t.tap(find.text('Go to Artist'));
    await t.pumpAndSettle();
    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(find.text('Unknown Artist'), findsOneWidget);
  });

  testWidgets('on the album screen the menu has no Go to Album', (t) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    await t.tap(find.text('Velvet Hours'));
    await t.pumpAndSettle();
    await longPress(t, 'Amber Lights');
    expect(find.text('Go to Album'), findsNothing);
    expect(find.text('Go to Artist'), findsOneWidget);

    await t.tap(find.text('Go to Artist'));
    await t.pumpAndSettle();
    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(backLabel('Velvet Hours'), findsOneWidget);
  });

  testWidgets('on the artist screen the menu has no Go to Artist', (t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
      ],
    );
    await t.tap(find.text('Artists'));
    await t.pumpAndSettle();
    await t.tap(find.text('Neon Harbor'));
    await t.pumpAndSettle();
    await longPress(t, 'Amber Lights');
    expect(find.text('Go to Artist'), findsNothing);
    expect(find.text('Go to Album'), findsOneWidget);
  });
}
