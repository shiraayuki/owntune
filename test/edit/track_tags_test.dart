import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/edit/track_tags.dart';

import '../support/fakes.dart';

void main() {
  final one = track(
    1,
    title: 'After the Rain',
    artist: 'Juno Vale',
    album: 'Paper Lanterns',
    trackNumber: 2,
    year: 2021,
  );
  final two = track(
    2,
    title: 'Blue Hour',
    artist: 'Juno Vale',
    album: 'Paper Lanterns',
    trackNumber: 3,
    year: 2021,
  );

  test('commonText of one song is its value', () {
    expect(commonText([one], TagField.title), 'After the Rain');
    expect(commonText([one], TagField.track), '2');
    expect(commonText([one], TagField.genre), '');
  });

  test('commonText of differing values is null', () {
    expect(commonText([one, two], TagField.title), isNull);
    expect(commonText([one, two], TagField.album), 'Paper Lanterns');
    expect(commonText([one, two], TagField.year), '2021');
  });

  test('apply sets only changed fields', () {
    const edit = TagEdit({TagField.album: 'Lanterns'});
    final a = edit.apply(TrackTags.of(one));
    final b = edit.apply(TrackTags.of(two));
    expect(a.album, 'Lanterns');
    expect(b.album, 'Lanterns');
    expect(a.title, 'After the Rain');
    expect(b.title, 'Blue Hour');
    expect(a.trackNumber, 2);
    expect(b.trackNumber, 3);
  });

  test('empty or blank text clears the field', () {
    const edit = TagEdit({TagField.artist: '  ', TagField.album: ''});
    final t = edit.apply(TrackTags.of(one));
    expect(t.artist, isNull);
    expect(t.album, isNull);
    expect(t.title, 'After the Rain');
  });

  test('numbers parse, blank clears', () {
    const edit = TagEdit({
      TagField.track: '07',
      TagField.year: '',
      TagField.disc: '2',
    });
    final t = edit.apply(TrackTags.of(one));
    expect(t.trackNumber, 7);
    expect(t.year, isNull);
    expect(t.discNumber, 2);
  });

  test('text is trimmed', () {
    final t = const TagEdit({
      TagField.title: '  Rain  ',
    }).apply(TrackTags.of(one));
    expect(t.title, 'Rain');
  });

  test('an empty edit changes nothing', () {
    const edit = TagEdit({});
    expect(edit.isEmpty, isTrue);
    expect(edit.apply(TrackTags.of(one)), TrackTags.of(one));
  });
}
