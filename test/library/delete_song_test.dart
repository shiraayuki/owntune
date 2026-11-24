import 'dart:async';
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoAlertDialog;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/songs_screen.dart';

import '../support/fakes.dart';

void main() {
  final songs = [
    track(1, title: 'After the Rain', artist: 'Juno Vale'),
    track(7, title: 'Amber Lights', artist: 'Neon Harbor'),
  ];

  Future<FakeTrackRepository> pump(WidgetTester t) async {
    final repo = FakeTrackRepository();
    await pumpApp(
      t,
      songs: songs,
      overrides: [trackRepositoryProvider.overrideWithValue(repo)],
    );
    await openLibraryTab(t);
    return repo;
  }

  Future<void> openDialog(WidgetTester t) async {
    await t.longPress(find.text('Amber Lights'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete from Library'));
    await t.pumpAndSettle();
  }

  testWidgets('long press on a song shows Delete from Library', (t) async {
    await pump(t);
    expect(find.text('Delete from Library'), findsNothing);

    await t.longPress(find.text('Amber Lights'));
    await t.pumpAndSettle();

    expect(find.text('Delete from Library'), findsOneWidget);
  });

  testWidgets('Delete from Library asks for confirmation', (t) async {
    final repo = await pump(t);
    await openDialog(t);

    expect(find.text('Delete "Amber Lights"?'), findsOneWidget);
    expect(
      find.text('The song will be removed from owntune and its file deleted.'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(repo.deleted, isEmpty);
  });

  testWidgets('Cancel closes the dialog without deleting', (t) async {
    final repo = await pump(t);
    await openDialog(t);

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(find.text('Delete "Amber Lights"?'), findsNothing);
    expect(repo.deleted, isEmpty);
  });

  testWidgets('Delete removes the long-pressed song by id', (t) async {
    final repo = await pump(t);
    await openDialog(t);

    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();

    expect(find.text('Delete "Amber Lights"?'), findsNothing);
    expect(repo.deleted, [7]);
  });

  testWidgets('the dialog uses the Cupertino style on iOS', (t) async {
    final repo = await pump(t);
    await openDialog(t);

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(repo.deleted, [7]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'a failing delete is shown with its error',
    (t) async {
      final repo = FakeTrackRepository(
        deleteError: const FileSystemException('Permission denied', '/x.mp3'),
      );
      await pumpApp(
        t,
        songs: songs,
        overrides: [trackRepositoryProvider.overrideWithValue(repo)],
      );
      await openLibraryTab(t);
      await openDialog(t);
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();

      expect(find.text('Could not delete "Amber Lights"'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              (w.data ?? '').contains('Permission denied'),
        ),
        findsOneWidget,
      );
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('Could not delete "Amber Lights"'), findsNothing);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('Delete still works if the list changed meanwhile', (t) async {
    final repo = FakeTrackRepository();
    final controller = StreamController<List<Track>>();
    addTearDown(controller.close);
    controller.add(songs);
    await pumpApp(
      t,
      songsStream: controller.stream,
      overrides: [trackRepositoryProvider.overrideWithValue(repo)],
    );
    await openLibraryTab(t);
    await openDialog(t);

    // E.g. a running import updates the list: the long-pressed row is
    // rebuilt elsewhere and its element is disposed.
    controller.add(const []);
    await t.pumpAndSettle();
    // The Songs and the (offstage) Albums tab both show the empty state.
    expect(
      find.text('Your library is empty', skipOffstage: false),
      findsWidgets,
    );
    expect(find.byType(SongRow, skipOffstage: false), findsNothing);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(repo.deleted, [7]);
  });
}
