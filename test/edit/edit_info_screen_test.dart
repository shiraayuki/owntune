import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/edit/edit_info_screen.dart';
import 'package:owntune/edit/track_tags.dart';
import 'package:owntune/library/artwork.dart';

import '../support/fakes.dart';

final _storage = LibraryStorage(Directory('/nonexistent/owntune'));

final _one = track(
  1,
  title: 'After the Rain',
  artist: 'Juno Vale',
  album: 'Paper Lanterns',
  genre: 'Indie Folk',
  trackNumber: 2,
  year: 2021,
);
final _two = track(
  2,
  title: 'Blue Hour',
  artist: 'The Quiet Coast',
  album: 'Paper Lanterns',
  trackNumber: 3,
  year: 2021,
);

Finder _field(TagField f) => find.byKey(Key('edit-field-${f.name}'));

String _text(WidgetTester t, TagField f) =>
    t.widget<TextField>(_field(f)).controller!.text;

void main() {
  Future<void> open(
    WidgetTester t,
    List<Track> tracks, {
    FakeTagWriter? writer,
    FakeTrackRepository? repo,
    FakeCoverPicker? picker,
    List<bool?>? results,
    LibraryStorage? storage,
  }) async {
    t.view.physicalSize = const Size(800, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pumpApp(
      t,
      songs: tracks,
      storage: storage ?? _storage,
      tagWriter: writer,
      editRepo: repo,
      coverPicker: picker,
    );
    final context = t.element(find.text('Songs').first);
    openEditInfo(context, tracks).then((r) => results?.add(r));
    await t.pumpAndSettle();
  }

  testWidgets("shows the song's values", (t) async {
    await open(t, [_one]);
    expect(find.text('Edit Info'), findsOneWidget);
    expect(_text(t, TagField.title), 'After the Rain');
    expect(_text(t, TagField.artist), 'Juno Vale');
    expect(_text(t, TagField.album), 'Paper Lanterns');
    expect(_text(t, TagField.albumArtist), '');
    expect(_text(t, TagField.genre), 'Indie Folk');
    expect(_text(t, TagField.track), '2');
    expect(_text(t, TagField.year), '2021');
  });

  testWidgets('Save is disabled until a field changes', (t) async {
    await open(t, [_one]);
    TextButton save() =>
        t.widget<TextButton>(find.byKey(const Key('edit-save')));
    expect(save().onPressed, isNull);
    await t.enterText(_field(TagField.genre), 'Folk');
    await t.pump();
    expect(save().onPressed, isNotNull);
    await t.enterText(_field(TagField.genre), 'Indie Folk');
    await t.pump();
    expect(save().onPressed, isNull);
  });

  testWidgets('saving writes the edit and closes', (t) async {
    final writer = FakeTagWriter();
    final repo = FakeTrackRepository();
    await open(t, [_one], writer: writer, repo: repo);
    await t.enterText(_field(TagField.title), 'After the Storm');
    await t.pump();
    await t.tap(find.byKey(const Key('edit-save')));
    await t.pumpAndSettle();
    expect(writer.written.values.single.title, 'After the Storm');
    expect(writer.written.values.single.artist, 'Juno Vale');
    expect(repo.updatedTags.single[1]!.title, 'After the Storm');
    expect(find.text('Edit Info'), findsNothing);
  });

  testWidgets('Cancel discards', (t) async {
    final writer = FakeTagWriter();
    await open(t, [_one], writer: writer);
    await t.enterText(_field(TagField.title), 'Nope');
    await t.tap(find.byKey(const Key('edit-cancel')));
    await t.pumpAndSettle();
    expect(writer.written, isEmpty);
    expect(find.text('Edit Info'), findsNothing);
  });

  testWidgets('bulk hides Title and Track and shows Mixed', (t) async {
    final writer = FakeTagWriter();
    await open(t, [_one, _two], writer: writer);
    expect(_field(TagField.title), findsNothing);
    expect(_field(TagField.track), findsNothing);
    expect(_text(t, TagField.artist), '');
    expect(
      t.widget<TextField>(_field(TagField.artist)).decoration!.hintText,
      'Mixed',
    );
    expect(_text(t, TagField.album), 'Paper Lanterns');
    expect(find.text('2 Songs'), findsOneWidget);

    await t.enterText(_field(TagField.genre), 'Folk');
    await t.pump();
    await t.tap(find.byKey(const Key('edit-save')));
    await t.pumpAndSettle();
    expect(writer.written, hasLength(2));
    final artists = {for (final w in writer.written.values) w.artist};
    expect(artists, {'Juno Vale', 'The Quiet Coast'});
    expect({for (final w in writer.written.values) w.genre}, {'Folk'});
  });

  testWidgets('number fields take digits only', (t) async {
    await open(t, [_one]);
    await t.enterText(_field(TagField.year), '19a9x9');
    await t.pump();
    expect(_text(t, TagField.year), '1999');
    await t.enterText(_field(TagField.year), '');
    await t.enterText(_field(TagField.year), '123456');
    await t.pump();
    expect(_text(t, TagField.year), '1234');
  });

  testWidgets('a failed save shows the songs that failed', (t) async {
    final writer = FakeTagWriter()
      ..failing[_storage.audioFile('hash2.mp3').path] = 'read-only file';
    await open(t, [_one, _two], writer: writer);
    await t.enterText(_field(TagField.genre), 'Folk');
    await t.pump();
    await t.tap(find.byKey(const Key('edit-save')));
    await t.pumpAndSettle();
    expect(find.text("Couldn't save 1 song"), findsOneWidget);
    expect(find.textContaining('Blue Hour'), findsOneWidget);
    expect(find.textContaining('read-only file'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Edit Info'), findsNothing);
  });

  testWidgets('saving the playing song reloads it', (t) async {
    t.view.physicalSize = const Size(800, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final engine = FakeAudioEngine();
    await pumpApp(t, songs: [_one, _two], storage: _storage, engine: engine);
    await t.tap(find.text('After the Rain'));
    await t.pumpAndSettle();
    expect(engine.loaded, ['hash1.mp3']);

    openEditInfo(t.element(find.text('Songs').first), [_one]);
    await t.pumpAndSettle();
    await t.enterText(_field(TagField.genre), 'Folk');
    await t.pump();
    await t.tap(find.byKey(const Key('edit-save')));
    await t.pumpAndSettle();
    expect(engine.loaded, ['hash1.mp3', 'hash1.mp3']);
  });

  testWidgets('the form closes the keyboard on scroll', (t) async {
    await open(t, [_one]);
    final list = t.widget<ListView>(
      find.descendant(
        of: find.byType(EditInfoScreen),
        matching: find.byType(ListView),
      ),
    );
    expect(
      list.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
  });

  group('cover', () {
    Uint8List png() {
      final image = img.Image(width: 60, height: 40);
      img.fill(image, color: img.ColorRgb8(0, 128, 255));
      return img.encodePng(image);
    }

    Finder art() => find.byKey(const Key('edit-cover-art'));
    TextButton save(WidgetTester t) =>
        t.widget<TextButton>(find.byKey(const Key('edit-save')));

    Future<void> openMenu(WidgetTester t) async {
      await t.tap(find.text('Edit Cover'));
      await t.pumpAndSettle();
    }

    /// Picking decodes and crops in isolates, which need real time.
    Future<void> settleIsolates(WidgetTester t) async {
      // Each file or isolate step needs real time, then a pump.
      for (var i = 0; i < 30; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      }
      await t.pumpAndSettle();
    }

    testWidgets('shows the song cover and Edit Cover', (t) async {
      await open(t, [track(1, title: 'Song', cover: 'a.jpg')]);
      final artwork = t.widget<Artwork>(
        find.descendant(of: art(), matching: find.byType(Artwork)),
      );
      expect(artwork.file!.path, _storage.coverFile('a.jpg').path);
      expect(find.text('Edit Cover'), findsOneWidget);
    });

    testWidgets('bulk with different covers shows Mixed', (t) async {
      await open(t, [
        track(1, title: 'A', cover: 'a.jpg'),
        track(2, title: 'B', cover: 'b.jpg'),
      ]);
      expect(
        find.descendant(of: art(), matching: find.text('Mixed')),
        findsOneWidget,
      );
    });

    testWidgets('menu lists photos, file, remove and cancel', (t) async {
      await open(t, [track(1, title: 'Song', cover: 'a.jpg')]);
      await openMenu(t);
      expect(find.text('Cover for “Song”'), findsOneWidget);
      expect(find.text('Choose from Photos'), findsOneWidget);
      expect(find.text('Choose File'), findsOneWidget);
      expect(find.text('Remove Cover'), findsOneWidget);
      expect(find.text('Cancel'), findsWidgets);
    });

    testWidgets('bulk menu names the number of songs', (t) async {
      await open(t, [track(1, cover: 'a.jpg'), track(2), track(3)]);
      await openMenu(t);
      expect(find.text('Cover for 3 songs'), findsOneWidget);
    });

    testWidgets('Remove Cover is hidden when no song has a cover', (t) async {
      await open(t, [_one]);
      await openMenu(t);
      expect(find.text('Choose from Photos'), findsOneWidget);
      expect(find.text('Remove Cover'), findsNothing);
    });

    testWidgets('picking and choosing sets a pending cover and enables Save', (
      t,
    ) async {
      final writer = FakeTagWriter();
      final picker = FakeCoverPicker(photo: png());
      final tmp = Directory.systemTemp.createTempSync('owntune_edit_cover');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final storage = LibraryStorage(tmp);
      await t.runAsync(storage.ensure);
      await open(t, [_one], writer: writer, picker: picker, storage: storage);
      await openMenu(t);
      await t.tap(find.text('Choose from Photos'));
      await settleIsolates(t);
      expect(find.text('Move and Scale'), findsOneWidget);
      await t.tap(find.text('Choose'));
      await settleIsolates(t);
      expect(find.text('Move and Scale'), findsNothing);
      expect(save(t).onPressed, isNotNull);
      expect(
        find.descendant(of: art(), matching: find.byType(Image)),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('edit-save')));
      await settleIsolates(t);
      final cover = writer.covers.values.single as CoverSet;
      expect(cover.mime, 'image/jpeg');
      expect(img.decodeJpg(cover.data)!.width, 40);
    });

    testWidgets(
      'shows a spinner and blocks editing while the image is processed',
      (t) async {
        await open(t, [_one], picker: FakeCoverPicker(photo: png()));
        await openMenu(t);
        await t.tap(find.text('Choose from Photos'));
        // Let the menu finish closing; the isolate needs real time, so the
        // spinner stays.
        await t.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const Key('edit-cover-busy')), findsOneWidget);
        expect(
          t.widget<TextButton>(find.byKey(const Key('edit-cancel'))).onPressed,
          isNotNull,
        );
        expect(
          t.widget<TextButton>(find.byKey(const Key('edit-save'))).onPressed,
          isNull,
        );
        await t.tap(find.text('Edit Cover'), warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 500));
        expect(find.text('Choose File'), findsNothing);
        await settleIsolates(t);
        expect(find.text('Move and Scale'), findsOneWidget);
        expect(find.byKey(const Key('edit-cover-busy')), findsNothing);
        await t.tap(find.text('Cancel').last);
        await t.pumpAndSettle();
      },
    );

    testWidgets('Remove Cover then Save writes CoverRemove', (t) async {
      final writer = FakeTagWriter();
      await open(t, [track(1, title: 'Song', cover: 'a.jpg')], writer: writer);
      await openMenu(t);
      await t.tap(find.text('Remove Cover'));
      await t.pumpAndSettle();
      final artwork = t.widget<Artwork>(
        find.descendant(of: art(), matching: find.byType(Artwork)),
      );
      expect(artwork.file, isNull);
      await t.tap(find.byKey(const Key('edit-save')));
      await t.pumpAndSettle();
      expect(writer.covers.values.single, isA<CoverRemove>());
    });

    testWidgets('an unreadable file shows an error and changes nothing', (
      t,
    ) async {
      final picker = FakeCoverPicker(file: Uint8List.fromList([1, 2, 3]));
      await open(t, [_one], picker: picker);
      await openMenu(t);
      await t.tap(find.text('Choose File'));
      await settleIsolates(t);
      expect(
        find.text("This image can't be read. Choose a JPEG or PNG."),
        findsOneWidget,
      );
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(save(t).onPressed, isNull);
    });

    testWidgets('cancelling the picker changes nothing', (t) async {
      final picker = FakeCoverPicker();
      await open(t, [_one], picker: picker);
      await openMenu(t);
      await t.tap(find.text('Choose from Photos'));
      await settleIsolates(t);
      expect(picker.photos, 1);
      expect(find.text('Move and Scale'), findsNothing);
      expect(save(t).onPressed, isNull);
    });
  });

  testWidgets('openEditInfo returns true after Save', (t) async {
    final results = <bool?>[];
    await open(t, [_one], results: results);
    await t.enterText(_field(TagField.genre), 'Folk');
    await t.pump();
    await t.tap(find.byKey(const Key('edit-save')));
    await t.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('openEditInfo returns false after Cancel', (t) async {
    final results = <bool?>[];
    await open(t, [_one], results: results);
    await t.tap(find.byKey(const Key('edit-cancel')));
    await t.pumpAndSettle();
    expect(results, [false]);
  });
}
