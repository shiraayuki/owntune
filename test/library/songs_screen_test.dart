import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/data/library_storage.dart';

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
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('A')).dy,
      lessThan(t.getTopLeft(find.text('After the Rain')).dy),
    );
    expect(
      t.getTopLeft(find.text('Amber Lights')).dy,
      lessThan(t.getTopLeft(find.text('B')).dy),
    );
    expect(
      t.getTopLeft(find.text('B')).dy,
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
}
