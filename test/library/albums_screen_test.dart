import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/navigation.dart';

import '../support/fakes.dart';

Future<void> openAlbumsTab(WidgetTester t) async {
  await t.tap(find.text('Albums'));
  await t.pumpAndSettle();
}

void main() {
  final songs = [
    track(1, title: 'a', artist: 'Neon Harbor', album: 'Velvet Hours'),
    track(2, title: 'b', artist: 'Juno Vale', album: 'Paper Lanterns'),
    track(3, title: 'c', artist: 'Juno Vale', album: 'Ember'),
    track(4, title: 'd', artist: 'Lumen Kids'),
  ];

  testWidgets('shows albums by album artist, then title', (t) async {
    await pumpApp(t, songs: songs);
    await openAlbumsTab(t);
    final titles = ['Ember', 'Paper Lanterns', 'Velvet Hours'];
    for (final title in titles) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Juno Vale'), findsNWidgets(2));
    expect(find.text('Neon Harbor'), findsOneWidget);
    // Two columns: Ember | Paper Lanterns, then Velvet Hours below.
    final ember = t.getTopLeft(find.text('Ember'));
    final paper = t.getTopLeft(find.text('Paper Lanterns'));
    final velvet = t.getTopLeft(find.text('Velvet Hours'));
    expect(paper.dy, ember.dy);
    expect(paper.dx, greaterThan(ember.dx));
    expect(velvet.dy, greaterThan(ember.dy));
    expect(velvet.dx, ember.dx);
  });

  testWidgets('empty library shows the empty state', (t) async {
    await pumpApp(t);
    await openAlbumsTab(t);
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('songs without album tags show the no-albums text', (t) async {
    await pumpApp(
      t,
      songs: [track(1, title: 'x', artist: 'Lumen Kids')],
    );
    await openAlbumsTab(t);
    expect(
      find.text(
        'No albums – songs without an album tag appear under Songs and '
        'Artists.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a card opens the album with back label Albums', (
    t,
  ) async {
    await pumpApp(t, songs: songs);
    await openAlbumsTab(t);
    await t.tap(find.text('Ember'));
    await t.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(NavRow), matching: find.text('Albums')),
      findsOneWidget,
    );
  });
}
