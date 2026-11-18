import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/import/import_sheets.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/settings/settings.dart';

import '../support/fakes.dart';

Future<void> pumpSheet(WidgetTester t, Widget sheet) => t.pumpWidget(
  MaterialApp(
    theme: buildTheme(Brightness.dark, AppSettings.defaults.accent),
    home: Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: sheet),
    ),
  ),
);

void main() {
  testWidgets('summary sheet shows the counts and the unsupported file', (
    t,
  ) async {
    var done = 0;
    await pumpSheet(
      t,
      ImportSummarySheet(summary: summary47, onDone: () => done++),
    );

    expect(find.text('Import complete'), findsOneWidget);
    expect(find.text('50 files checked'), findsOneWidget);
    expect(find.text('47 songs added'), findsOneWidget);
    expect(find.text('8 albums · 7 artists'), findsOneWidget);
    expect(find.text('2 duplicates skipped'), findsOneWidget);
    expect(find.text('Already in your library'), findsOneWidget);
    expect(find.text('1 file not supported'), findsOneWidget);
    expect(find.textContaining('evening-walk.ogg'), findsOneWidget);

    await t.tap(find.text('Done'));
    expect(done, 1);
  });

  testWidgets('summary sheet uses singular forms and hides empty rows', (
    t,
  ) async {
    const summary = ImportSummary(
      added: 1,
      duplicates: 0,
      unsupported: ['a.ogg', 'broken.mp3'],
      albums: 1,
      artists: 1,
    );
    await pumpSheet(t, ImportSummarySheet(summary: summary, onDone: () {}));

    expect(find.text('3 files checked'), findsOneWidget);
    expect(find.text('1 song added'), findsOneWidget);
    expect(find.text('1 album · 1 artist'), findsOneWidget);
    expect(find.textContaining('duplicate'), findsNothing);
    expect(find.text('2 files not supported'), findsOneWidget);
    expect(find.textContaining('a.ogg, broken.mp3'), findsOneWidget);
  });

  testWidgets('summary sheet with nothing added', (t) async {
    const summary = ImportSummary(
      added: 0,
      duplicates: 1,
      unsupported: [],
      albums: 0,
      artists: 0,
    );
    await pumpSheet(t, ImportSummarySheet(summary: summary, onDone: () {}));

    expect(find.text('1 file checked'), findsOneWidget);
    expect(find.text('0 songs added'), findsOneWidget);
    expect(find.text('1 duplicate skipped'), findsOneWidget);
    expect(find.textContaining('not supported'), findsNothing);
  });

  testWidgets('progress sheet shows count, bar, current file and Hide', (
    t,
  ) async {
    var hidden = 0;
    await pumpSheet(
      t,
      ImportProgressSheet(
        progress: const ImportProgress(
          done: 23,
          total: 50,
          currentName: 'Kettle & Pine – Dust & Gold.flac',
        ),
        onHide: () => hidden++,
      ),
    );

    expect(find.text('Importing music…'), findsOneWidget);
    expect(find.text('23 of 50 files'), findsOneWidget);
    expect(
      find.text('Reading tags: Kettle & Pine – Dust & Gold.flac'),
      findsOneWidget,
    );
    final bar = t.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.46, 1e-9));

    await t.tap(find.text('Hide – keep importing'));
    expect(hidden, 1);
  });

  testWidgets('progress sheet for a single file', (t) async {
    await pumpSheet(
      t,
      ImportProgressSheet(
        progress: const ImportProgress(done: 0, total: 1, currentName: 'a.mp3'),
        onHide: () {},
      ),
    );
    expect(find.text('0 of 1 file'), findsOneWidget);
  });

  testWidgets('failed sheet shows the error as selectable text', (t) async {
    var done = 0;
    await pumpSheet(
      t,
      ImportFailedSheet(
        message: 'FileSystemException: disk full',
        onDone: () => done++,
      ),
    );
    expect(find.text('Import failed'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
    await t.tap(find.text('Done'));
    expect(done, 1);
  });
}
