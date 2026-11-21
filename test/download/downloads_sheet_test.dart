import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/download/downloads_sheet.dart';

import '../support/fakes.dart';

const mib = 1 << 20;

void main() {
  Future<FakeDownloadController> show(
    WidgetTester t,
    List<DownloadJob> jobs,
  ) async {
    final downloads = FakeDownloadController(jobs);
    await t.pumpWidget(
      ProviderScope(
        overrides: [downloadControllerProvider.overrideWith(() => downloads)],
        child: MaterialApp(
          theme: buildTheme(Brightness.light, const Color(0xffff7a59)),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDownloadsSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return downloads;
  }

  Finder row(int id) => find.byKey(ValueKey('download-row-$id'));

  Finder inRow(int id, Finder f) => find.descendant(of: row(id), matching: f);

  testWidgets('shows each phase\'s status line and the count', (t) async {
    await show(t, [
      downloadJob(1, 'a', phase: DownloadPhase.waiting),
      downloadJob(
        2,
        'b',
        phase: DownloadPhase.downloading,
        received: (1.2 * mib).round(),
        total: 3 * mib,
      ),
      downloadJob(3, 'c', phase: DownloadPhase.importing),
      downloadJob(4, 'd', phase: DownloadPhase.done),
      downloadJob(
        5,
        'e',
        phase: DownloadPhase.duplicate,
        error: 'Already in your library',
      ),
      downloadJob(6, 'f', phase: DownloadPhase.cancelled),
      downloadJob(
        7,
        'g',
        phase: DownloadPhase.failed,
        error: 'YouTube: Video unavailable',
      ),
    ]);
    expect(find.text('Downloads'), findsOneWidget);
    expect(
      find.text('4 of 7 done · keep owntune open until they finish'),
      findsOneWidget,
    );
    expect(inRow(1, find.text('Waiting')), findsOneWidget);
    expect(inRow(2, find.text('1.2 of 3.0 MB')), findsOneWidget);
    expect(inRow(3, find.text('Adding to library…')), findsOneWidget);
    expect(inRow(4, find.text('Added to your library')), findsOneWidget);
    expect(inRow(5, find.text('Already in your library')), findsOneWidget);
    expect(inRow(6, find.text('Cancelled')), findsOneWidget);
    expect(
      inRow(7, find.text("Couldn't download: YouTube: Video unavailable")),
      findsOneWidget,
    );
  });

  testWidgets('rows do not rebuild on progress of another job', (t) async {
    final downloads = await show(t, [
      downloadJob(
        1,
        'a',
        phase: DownloadPhase.downloading,
        received: 1,
        total: mib,
      ),
      downloadJob(2, 'b'),
    ]);
    // A row that did not rebuild keeps the very same child widgets.
    Widget firstText(int id) => t.widget(inRow(id, find.byType(Text)).first);
    final one = firstText(1);
    final two = firstText(2);
    downloads.jobs = [
      downloadJob(
        1,
        'a',
        phase: DownloadPhase.downloading,
        received: 9,
        total: mib,
      ),
      downloads.state[1],
    ];
    await t.pump();
    expect(identical(firstText(1), one), isFalse);
    expect(identical(firstText(2), two), isTrue);
  });

  testWidgets('X cancels a waiting or running job', (t) async {
    final downloads = await show(t, [
      downloadJob(1, 'a', phase: DownloadPhase.downloading, total: 10),
      downloadJob(2, 'b', phase: DownloadPhase.done),
    ]);
    expect(inRow(2, find.byKey(const Key('download-cancel'))), findsNothing);
    await t.tap(inRow(1, find.byKey(const Key('download-cancel'))));
    expect(downloads.cancelled, [1]);
  });

  testWidgets('Retry retries a failed or cancelled job', (t) async {
    final downloads = await show(t, [
      downloadJob(1, 'a', phase: DownloadPhase.failed, error: 'No connection'),
      downloadJob(2, 'b', phase: DownloadPhase.cancelled),
    ]);
    await t.tap(inRow(1, find.text('Retry')));
    await t.tap(inRow(2, find.text('Retry')));
    expect(downloads.retried, [1, 2]);
  });

  testWidgets('Done clears finished jobs and closes', (t) async {
    final downloads = await show(t, [
      downloadJob(1, 'a', phase: DownloadPhase.done),
    ]);
    expect(find.text('1 of 1 done'), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(downloads.cleared, 1);
    expect(find.text('Downloads'), findsNothing);
  });
}
