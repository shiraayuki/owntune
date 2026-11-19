import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/library/section_index.dart';
import 'package:owntune/library/song_sort.dart';
import 'package:owntune/settings/settings.dart';

import '../support/fakes.dart';

void main() {
  final songs = [
    track(
      1,
      title: 'After the Rain',
      artist: 'Juno Vale',
      album: 'Paper Lanterns',
    ),
    track(
      2,
      title: 'Amber Lights',
      artist: 'Neon Harbor',
      album: 'Velvet Hours',
    ),
    track(3, title: 'Backroads', artist: 'Kettle & Pine', album: 'Northbound'),
    track(4, originalName: 'demo_3.wav'),
  ];

  testWidgets('shows section headers A and B', (t) async {
    await pumpApp(t, songs: songs);
    Finder header(String l) => find.byKey(ValueKey('section-$l'));
    expect(header('A'), findsOneWidget);
    expect(header('B'), findsOneWidget);
    expect(header('D'), findsOneWidget);
    expect(
      t.getTopLeft(header('A')).dy,
      lessThan(t.getTopLeft(find.text('After the Rain')).dy),
    );
    expect(
      t.getTopLeft(find.text('Amber Lights')).dy,
      lessThan(t.getTopLeft(header('B')).dy),
    );
    expect(
      t.getTopLeft(header('B')).dy,
      lessThan(t.getTopLeft(find.text('Backroads')).dy),
    );
  });

  testWidgets('shows title and artist · album per row', (t) async {
    await pumpApp(t, songs: songs);
    expect(find.text('After the Rain'), findsOneWidget);
    expect(find.text('Juno Vale · Paper Lanterns'), findsOneWidget);
    expect(find.text('Kettle & Pine · Northbound'), findsOneWidget);
  });

  testWidgets('shows demo_3 with Unknown Artist', (t) async {
    await pumpApp(t, songs: songs);
    expect(find.text('demo_3'), findsOneWidget);
    expect(find.text('Unknown Artist'), findsOneWidget);
  });

  testWidgets('a song without cover shows the placeholder icon', (t) async {
    await pumpApp(t, songs: [track(1, title: 'Song')]);
    expect(find.byIcon(CupertinoIcons.music_note), findsWidgets);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a song with cover shows the downscaled cover file', (t) async {
    final tmp = Directory.systemTemp.createTempSync('owntune_songs_test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final storage = LibraryStorage(tmp);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await pumpApp(
      t,
      songs: [track(1, title: 'Song', cover: 'c0ffee.png')],
      storage: storage,
    );

    final image = t.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.width, 144);
    expect(
      (provider.imageProvider as FileImage).file.path,
      storage.coverFile('c0ffee.png').path,
    );
  });

  testWidgets('empty library shows the empty state', (t) async {
    await pumpApp(t);
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Import Music'), findsOneWidget);
    expect(find.text('MP3 · M4A/AAC · FLAC · WAV'), findsOneWidget);
  });

  testWidgets('Import Music opens the picker and imports the picked files', (
    t,
  ) async {
    final importer = FakeImporter();
    final picker = FakePicker(['/a/one.mp3', '/a/two.flac']);
    await pumpApp(t, importer: importer, picker: picker);

    await t.tap(find.text('Import Music'));
    await t.pumpAndSettle();

    expect(picker.picks, 1);
    expect(importer.calls, [
      ['/a/one.mp3', '/a/two.flac'],
    ]);
    expect(find.text('Importing music…'), findsOneWidget);
  });

  testWidgets('cancelling the picker does nothing', (t) async {
    final importer = FakeImporter();
    final picker = FakePicker();
    await pumpApp(t, importer: importer, picker: picker);

    await t.tap(find.text('Import Music'));
    await t.pumpAndSettle();

    expect(picker.picks, 1);
    expect(importer.calls, isEmpty);
    expect(find.text('Importing music…'), findsNothing);
  });

  testWidgets('shows the song count and sort order', (t) async {
    await pumpApp(t, songs: songs);
    expect(find.text('4 songs · sorted by title'), findsOneWidget);
  });

  testWidgets('a single song is counted in the singular', (t) async {
    await pumpApp(t, songs: [songs.first]);
    expect(find.text('1 song · sorted by title'), findsOneWidget);
  });

  testWidgets('recently added has no section headers', (t) async {
    await pumpApp(
      t,
      songs: songs,
      overrides: [
        initialSettingsProvider.overrideWithValue(
          AppSettings.defaults.copyWith(songSort: SongSort.added),
        ),
      ],
    );
    expect(find.text('4 songs · sorted by recently added'), findsOneWidget);
    expect(find.byKey(const ValueKey('section-A')), findsNothing);
    expect(find.byType(SectionIndex), findsNothing);
  });

  group('A–Z index', () {
    // Six songs per letter A–F, so D starts well below the first screen.
    final many = [
      for (final (i, l) in ['A', 'B', 'C', 'D', 'E', 'F'].indexed)
        for (var n = 0; n < 6; n++) track(i * 10 + n, title: '$l song $n'),
    ];
    Finder strip(String l) =>
        find.descendant(of: find.byType(SectionIndex), matching: find.text(l));

    testWidgets('tapping D scrolls the D header to the top', (t) async {
      await pumpApp(t, songs: many);
      expect(find.byKey(const ValueKey('section-D')), findsNothing);

      await t.tap(strip('D'));
      await t.pumpAndSettle();

      expect(
        t.getTopLeft(find.byKey(const ValueKey('section-D'))).dy,
        t.getTopLeft(find.byType(ListView)).dy,
      );
    });

    testWidgets('tapping a letter without songs jumps to the next one', (
      t,
    ) async {
      await pumpApp(t, songs: many);
      await t.tap(strip('#'));
      await t.pumpAndSettle();
      // Nothing after # — the list stays where it is.
      expect(find.byKey(const ValueKey('section-A')), findsOneWidget);
    });

    testWidgets('short screen collapses the index without overflow', (t) async {
      t.view.physicalSize = const Size(1600, 700);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await pumpApp(t, songs: many);
      expect(strip('•'), findsWidgets);
      expect(strip('A'), findsOneWidget);
      expect(strip('#'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
