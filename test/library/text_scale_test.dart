import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/library/section_index.dart';
import 'package:owntune/library/songs_screen.dart';

import '../support/fakes.dart';

void main() {
  // iOS "xxxLarge", the largest size before the accessibility sizes.
  const scale = 1.35;

  final many = [
    for (final (i, l) in ['A', 'B', 'C', 'D', 'E', 'F'].indexed)
      for (var n = 0; n < 6; n++)
        track(
          i * 10 + n,
          title: '$l song $n',
          artist: 'Artist',
          album: 'Album $l',
        ),
  ];

  testWidgets('songs rows grow with the text size and the index still jumps', (
    t,
  ) async {
    // iPhone 14: the 800×600 default leaves too little room for the full
    // A–Z strip under the sub-tabs and above the tab bar.
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(t, songs: many);
    await openLibraryTab(t);
    expect(t.takeException(), isNull);

    await t.tap(
      find.descendant(of: find.byType(SectionIndex), matching: find.text('D')),
    );
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(find.byKey(const ValueKey('section-D'))).dy,
      t.getTopLeft(find.byType(ListView)).dy,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('album cards grow with the text size', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(t, songs: many);
    await openLibraryTab(t);
    await t.tap(find.text('Albums'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('library sub-tabs fit at large text', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(t, songs: many);
    await openLibraryTab(t);
    expect(t.takeException(), isNull);
    for (final sub in ['Artists', 'Songs']) {
      await t.tap(find.text(sub));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: sub);
    }
  });

  for (final factor in [1.0, 1.5]) {
    testWidgets('a song row is as high as SongRow.extentFor at $factor', (
      t,
    ) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(
              LibraryStorage(Directory('/nonexistent/owntune')),
            ),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.light, const Color(0xff0a84ff)),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(factor)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SongRow(
                  track: track(1, title: 'A song', artist: 'Artist'),
                  scope: const SongMenuScope(backLabel: 'Library'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('song-more-1')), findsOneWidget);
      expect(
        t.getSize(find.byType(SongRow)).height,
        SongRow.extentFor(TextScaler.linear(factor)),
      );
    });
  }
}
