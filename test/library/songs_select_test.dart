import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/playlist_repository.dart';

import '../support/fakes.dart';

final _songs = [
  track(1, title: 'Amber'),
  track(2, title: 'Blue'),
  track(3, title: 'Cold'),
];

Future<void> _startSelecting(WidgetTester t) async {
  await t.tap(find.byTooltip('More'));
  await t.pumpAndSettle();
  await t.tap(find.text('Select'));
  await t.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester t, {
  FakeAudioEngine? engine,
  FakeTrackRepository? repo,
}) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await pumpApp(
    t,
    songs: _songs,
    engine: engine,
    editRepo: repo,
    overrides: [
      if (repo != null) trackRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

Finder _bar(String label) => find.descendant(
  of: find.byKey(const Key('selection-bar')),
  matching: find.text(label),
);

bool _enabled(WidgetTester t, String label) =>
    t
        .widget<InkWell>(
          find.ancestor(of: _bar(label), matching: find.byType(InkWell)).first,
        )
        .onTap !=
    null;

Future<void> _select(WidgetTester t, List<String> titles) async {
  await _startSelecting(t);
  for (final title in titles) {
    await t.tap(find.text(title));
    await t.pump();
  }
}

void main() {
  testWidgets('Select is in the more menu only on Songs', (t) async {
    await _pump(t);
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(find.text('Select'), findsOneWidget);
    await t.tapAt(const Offset(10, 1500));
    await t.pumpAndSettle();
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(find.text('Select'), findsNothing);
  });

  testWidgets('select mode shows the count and Done instead of the buttons', (
    t,
  ) async {
    await _pump(t);
    await _startSelecting(t);
    expect(find.text('Select Songs'), findsOneWidget);
    expect(find.byTooltip('More'), findsNothing);
    expect(find.byKey(const Key('import-button')), findsNothing);
    expect(find.byKey(const Key('selection-done')), findsOneWidget);
    await t.tap(find.text('Amber'));
    await t.pump();
    expect(find.text('1 Selected'), findsOneWidget);
    await t.tap(find.text('Amber'));
    await t.pump();
    expect(find.text('Select Songs'), findsOneWidget);
  });

  testWidgets('rows show check circles and do not play', (t) async {
    final engine = FakeAudioEngine();
    await _pump(t, engine: engine);
    await _startSelecting(t);
    await t.tap(find.text('Blue'));
    await t.pump();
    expect(engine.loaded, isEmpty);
    expect(
      find.descendant(
        of: find.byKey(const Key('song-check-2')),
        matching: find.byIcon(CupertinoIcons.checkmark),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('song-check-1')),
        matching: find.byIcon(CupertinoIcons.checkmark),
      ),
      findsNothing,
    );
  });

  testWidgets('meta line says tap to select', (t) async {
    await _pump(t);
    await _startSelecting(t);
    expect(find.text('3 songs · tap to select'), findsOneWidget);
  });

  testWidgets('tab bar and mini player are replaced by the selection bar', (
    t,
  ) async {
    await _pump(t);
    await _startSelecting(t);
    expect(find.text('Home'), findsNothing);
    expect(find.byKey(const Key('selection-bar')), findsOneWidget);
  });

  testWidgets('Done ends selection', (t) async {
    await _pump(t);
    await _startSelecting(t);
    await t.tap(find.byKey(const Key('selection-done')));
    await t.pumpAndSettle();
    expect(find.text('Library'), findsWidgets);
    expect(find.byKey(const Key('selection-bar')), findsNothing);
  });

  testWidgets('switching the sub-tab ends selection', (t) async {
    await _pump(t);
    await _startSelecting(t);
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('selection-bar')), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('back ends selection', (t) async {
    await _pump(t);
    await _startSelecting(t);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('selection-bar')), findsNothing);
    expect(find.text('Amber'), findsOneWidget);
  });

  testWidgets('filtered-out songs stay selected', (t) async {
    await _pump(t);
    await _startSelecting(t);
    await t.tap(find.text('Amber'));
    await t.pump();
    await t.enterText(find.byType(TextField).first, 'blue');
    await t.pumpAndSettle();
    expect(find.text('Amber'), findsNothing);
    await t.enterText(find.byType(TextField).first, '');
    await t.pumpAndSettle();
    expect(find.text('1 Selected'), findsOneWidget);
  });

  group('selection bar', () {
    testWidgets('shows Edit Info, Add to Playlist and Delete', (t) async {
      await _pump(t);
      await _startSelecting(t);
      expect(_bar('Edit Info'), findsOneWidget);
      expect(_bar('Add to Playlist'), findsOneWidget);
      expect(_bar('Delete'), findsOneWidget);
      expect(_enabled(t, 'Edit Info'), isFalse);
      expect(_enabled(t, 'Delete'), isFalse);
      expect(_enabled(t, 'Add to Playlist'), isFalse);
      await t.tap(find.text('Amber'));
      await t.pump();
      expect(_enabled(t, 'Edit Info'), isTrue);
      expect(_enabled(t, 'Delete'), isTrue);
      expect(_enabled(t, 'Add to Playlist'), isTrue);
    });

    testWidgets('Edit Info opens the bulk editor; Save ends selection', (
      t,
    ) async {
      await _pump(t);
      await _select(t, ['Amber', 'Blue']);
      await t.tap(_bar('Edit Info'));
      await t.pumpAndSettle();
      expect(find.text('2 Songs'), findsOneWidget);
      expect(find.byKey(const Key('edit-field-title')), findsNothing);
      await t.enterText(find.byKey(const Key('edit-field-genre')), 'Folk');
      await t.pump();
      await t.tap(find.byKey(const Key('edit-save')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('selection-bar')), findsNothing);
    });

    testWidgets('Edit Info Cancel keeps the selection', (t) async {
      await _pump(t);
      await _select(t, ['Amber', 'Blue']);
      await t.tap(_bar('Edit Info'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('edit-cancel')));
      await t.pumpAndSettle();
      expect(find.text('2 Selected'), findsOneWidget);
    });

    testWidgets('one selected opens the single editor', (t) async {
      await _pump(t);
      await _select(t, ['Blue']);
      await t.tap(_bar('Edit Info'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('edit-field-title')), findsOneWidget);
    });

    testWidgets('Add to Playlist adds all selected and ends the selection', (
      t,
    ) async {
      final db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      addTearDown(db.close);
      final playlists = PlaylistRepository(
        db,
        LibraryStorage(Directory('/nonexistent/owntune')),
        hash: (_) => 'h',
      );
      await t.runAsync(() => playlists.create('Rainy Days'));
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pumpApp(t, songs: _songs, playlists: playlists);
      await _select(t, ['Cold', 'Amber']);
      await t.tap(_bar('Add to Playlist'));
      await t.pumpAndSettle();
      expect(find.text('2 songs'), findsOneWidget);
      await t.tap(find.text('Rainy Days'));
      await t.pumpAndSettle();

      final entries = await t.runAsync(() => playlists.watchEntries().first);
      entries!.sort((a, b) => a.position.compareTo(b.position));
      // In library order, not in the order of the taps.
      expect([for (final e in entries) e.trackId], [1, 3]);
      expect(find.byKey(const Key('selection-bar')), findsNothing);
      expect(find.text('Added to Rainy Days'), findsOneWidget);
    });

    testWidgets('Add to Playlist cancelled keeps the selection', (t) async {
      await _pump(t);
      await _select(t, ['Amber']);
      await t.tap(_bar('Add to Playlist'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('1 Selected'), findsOneWidget);
    });

    testWidgets('Delete asks and deletes all selected', (t) async {
      final repo = FakeTrackRepository();
      await _pump(t, repo: repo);
      await _select(t, ['Amber', 'Blue']);
      await t.tap(_bar('Delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete 2 songs?'), findsOneWidget);
      expect(
        find.text(
          'The songs will be removed from owntune and their files deleted.',
        ),
        findsOneWidget,
      );
      await t.tap(find.widgetWithText(TextButton, 'Delete'));
      await t.pumpAndSettle();
      expect(repo.deleted.toSet(), {1, 2});
      expect(find.byKey(const Key('selection-bar')), findsNothing);
    });

    testWidgets('Delete cancel keeps the selection', (t) async {
      final repo = FakeTrackRepository();
      await _pump(t, repo: repo);
      await _select(t, ['Amber']);
      await t.tap(_bar('Delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete 1 song?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(repo.deleted, isEmpty);
      expect(find.text('1 Selected'), findsOneWidget);
    });

    testWidgets('failed deletes are listed', (t) async {
      final repo = FakeTrackRepository(deleteError: Exception('disk gone'));
      await _pump(t, repo: repo);
      await _select(t, ['Amber', 'Blue']);
      await t.tap(_bar('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'Delete'));
      await t.pumpAndSettle();
      expect(find.text("Couldn't delete 2 songs"), findsOneWidget);
      final text = t.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(text, contains('Amber'));
      expect(text, contains('Blue'));
      expect(text, contains('disk gone'));
    });

    testWidgets('actions include songs hidden by the search', (t) async {
      final repo = FakeTrackRepository();
      await _pump(t, repo: repo);
      await _select(t, ['Amber']);
      await t.enterText(find.byType(TextField).first, 'blue');
      await t.pumpAndSettle();
      await t.tap(find.text('Blue'));
      await t.pump();
      await t.tap(_bar('Delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete 2 songs?'), findsOneWidget);
      await t.tap(find.widgetWithText(TextButton, 'Delete'));
      await t.pumpAndSettle();
      expect(repo.deleted.toSet(), {1, 2});
    });
  });

  testWidgets('the "…" buttons are hidden in selection mode', (t) async {
    await _pump(t);
    expect(find.byKey(const Key('song-more-1')), findsOneWidget);
    await _startSelecting(t);
    expect(find.byKey(const Key('song-more-1')), findsNothing);
    expect(find.byKey(const Key('song-more-2')), findsNothing);
  });
}
