import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/download_sheet.dart';
import 'package:owntune/edit/track_tags.dart';

import '../support/fakes.dart';

void main() {
  Future<FakeDownloadController> show(
    WidgetTester t,
    OnlineResult result, {
    List<String> inLibrary = const [],
  }) async {
    final downloads = FakeDownloadController();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          downloadControllerProvider.overrideWith(() => downloads),
          tracksProvider.overrideWith(
            (ref) => Stream.value([
              for (final (i, key) in inLibrary.indexed)
                track(i + 1, sourceKey: key),
            ]),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light, const Color(0xffff7a59)),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDownloadSheet(context, result),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return downloads;
  }

  String field(WidgetTester t, String key) =>
      t.widget<TextField>(find.byKey(Key(key))).controller!.text;

  testWidgets('Songs prefill title, artist, album', (t) async {
    await show(t, onlineResult('abc'));
    expect(field(t, 'download-title'), 'Numb');
    expect(field(t, 'download-artist'), 'Linkin Park');
    expect(field(t, 'download-album'), 'Meteora');
    expect(find.text('From YouTube Music · M4A, 128 kbps'), findsOneWidget);
  });

  testWidgets('Videos prefill from guessTags', (t) async {
    await show(
      t,
      onlineResult(
        'vid',
        source: OnlineSourceId.youtube,
        title: 'Numb (Official Music Video) [4K UPGRADE] – Linkin Park',
        channel: 'Linkin Park',
      ),
    );
    expect(field(t, 'download-title'), 'Numb');
    expect(field(t, 'download-artist'), 'Linkin Park');
    expect(field(t, 'download-album'), '');
    expect(
      find.text(
        'From YouTube · "Numb (Official Music Video) [4K UPGRADE] – Linkin '
        'Park" by Linkin Park · M4A, 128 kbps',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Download enqueues the edited tags and closes', (t) async {
    final downloads = await show(t, onlineResult('abc'));
    await t.enterText(find.byKey(const Key('download-album')), '  ');
    await t.enterText(find.byKey(const Key('download-title')), 'Numb (Live)');
    await t.tap(find.byKey(const Key('download-confirm')));
    await t.pumpAndSettle();
    final call = downloads.enqueued.single;
    expect(call.result.id, 'abc');
    expect(call.tags.title, 'Numb (Live)');
    expect(call.tags.artist, 'Linkin Park');
    expect(call.tags.album, isNull);
    expect(find.byType(DownloadSheet), findsNothing);
  });

  testWidgets('an empty title disables Download', (t) async {
    final downloads = await show(t, onlineResult('abc'));
    await t.enterText(find.byKey(const Key('download-title')), ' ');
    await t.pump();
    await t.tap(find.byKey(const Key('download-confirm')));
    await t.pumpAndSettle();
    expect(downloads.enqueued, isEmpty);
  });

  testWidgets('a song in the library shows a disabled In Library button', (
    t,
  ) async {
    final downloads = await show(
      t,
      onlineResult('abc'),
      inLibrary: ['youtube:abc'],
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('download-confirm')),
        matching: find.text('In Library'),
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('download-confirm')));
    await t.pumpAndSettle();
    expect(downloads.enqueued, isEmpty);
  });

  testWidgets('tapping Download twice enqueues once', (t) async {
    final downloads = await show(t, onlineResult('abc'));
    await t.tap(find.byKey(const Key('download-confirm')));
    await t.tap(find.byKey(const Key('download-confirm')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(downloads.enqueued, hasLength(1));
  });

  testWidgets('the sheet shows "From SoundCloud · M4A, 96 kbps" for kbps 96', (
    t,
  ) async {
    await show(
      t,
      onlineResult('9', source: OnlineSourceId.soundcloud, kbps: 96),
    );
    expect(find.text('From SoundCloud · M4A, 96 kbps'), findsOneWidget);
  });

  testWidgets('the sheet shows the 160 kbps line', (t) async {
    await show(
      t,
      onlineResult('9', source: OnlineSourceId.soundcloud, kbps: 160),
    );
    expect(find.text('From SoundCloud · M4A, 160 kbps'), findsOneWidget);
  });

  testWidgets('Download enqueues the edited title/artist/album with the '
      "result's genre and year", (t) async {
    final downloads = await show(
      t,
      onlineResult(
        '9',
        source: OnlineSourceId.soundcloud,
        title: 'Smoke Signals',
        artist: 'SRY4U',
        album: null,
        genre: 'Hip-hop',
        year: 2023,
        kbps: 160,
      ),
    );
    expect(field(t, 'download-title'), 'Smoke Signals');
    expect(field(t, 'download-artist'), 'SRY4U');
    await t.enterText(find.byKey(const Key('download-title')), 'Smoke');
    await t.enterText(find.byKey(const Key('download-artist')), 'Sry4u');
    await t.enterText(find.byKey(const Key('download-album')), 'EP');
    await t.tap(find.byKey(const Key('download-confirm')));
    await t.pumpAndSettle();
    expect(
      downloads.enqueued.single.tags,
      const TrackTags(
        title: 'Smoke',
        artist: 'Sry4u',
        album: 'EP',
        genre: 'Hip-hop',
        year: 2023,
      ),
    );
  });
}
