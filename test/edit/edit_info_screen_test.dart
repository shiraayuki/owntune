import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/edit/edit_info_screen.dart';
import 'package:owntune/edit/track_tags.dart';

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
  }) async {
    t.view.physicalSize = const Size(800, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pumpApp(
      t,
      songs: tracks,
      storage: _storage,
      tagWriter: writer,
      editRepo: repo,
    );
    final context = t.element(find.text('Songs').first);
    openEditInfo(context, tracks);
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
}
