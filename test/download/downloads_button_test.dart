import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/download/downloads_sheet.dart';

import '../support/fakes.dart';

void main() {
  final button = find.byKey(const Key('downloads-button'));

  Finder badge(String text) => find.descendant(
    of: button,
    matching: find.byWidgetPredicate((w) => w is Text && w.data == text),
  );

  testWidgets('hidden with no jobs, in the shell title row otherwise', (
    t,
  ) async {
    final downloads = FakeDownloadController();
    await pumpApp(t, downloads: downloads);
    expect(button, findsNothing);
    downloads.jobs = [
      downloadJob(1, 'a', phase: DownloadPhase.downloading, total: 10),
      downloadJob(2, 'b'),
      downloadJob(3, 'c', phase: DownloadPhase.done),
    ];
    await t.pump();
    expect(button, findsOneWidget);
    expect(badge('2'), findsOneWidget);
  });

  testWidgets('opens the downloads sheet', (t) async {
    final downloads = FakeDownloadController([downloadJob(1, 'a')]);
    await pumpApp(t, downloads: downloads);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.byType(DownloadsSheet), findsOneWidget);
  });

  testWidgets('shows a warning while a job failed', (t) async {
    final downloads = FakeDownloadController([
      downloadJob(1, 'a', phase: DownloadPhase.failed, error: 'x'),
      downloadJob(2, 'b', phase: DownloadPhase.done),
    ]);
    await pumpApp(t, downloads: downloads);
    expect(button, findsOneWidget);
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(CupertinoIcons.exclamationmark),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a check for 3 s after the last success, then hidden', (t) async {
    final downloads = FakeDownloadController([
      downloadJob(1, 'a', phase: DownloadPhase.downloading, total: 10),
    ]);
    await pumpApp(t, downloads: downloads);
    expect(button, findsOneWidget);

    downloads.jobs = [downloadJob(1, 'a', phase: DownloadPhase.done)];
    await t.pump();
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(CupertinoIcons.checkmark),
      ),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    expect(button, findsNothing);
  });

  testWidgets('Search Online shows the button too', (t) async {
    final downloads = FakeDownloadController([downloadJob(1, 'a')]);
    await pumpApp(t, downloads: downloads);
    await t.tap(find.byKey(const Key('import-button')));
    await t.pumpAndSettle();
    await t.tap(find.text('Search Online'));
    await t.pumpAndSettle();
    expect(button, findsOneWidget);
  });
}
