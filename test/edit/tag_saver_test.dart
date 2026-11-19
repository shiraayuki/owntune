import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/edit/tag_saver.dart';
import 'package:owntune/edit/track_tags.dart';

import '../support/fakes.dart';

void main() {
  late FakeTrackRepository repo;
  late FakeTagWriter writer;
  late TagSaver saver;
  final storage = LibraryStorage(Directory('/lib/owntune'));

  setUp(() {
    repo = FakeTrackRepository();
    writer = FakeTagWriter();
    saver = TagSaver(write: writer.call, storage: storage, repo: repo);
  });

  final a = track(1, title: 'A', album: 'Old');
  final b = track(2, title: 'B', album: 'Old');

  test('writes the file, then the row', () async {
    final failures = await saver.save([
      a,
    ], const TagEdit({TagField.album: 'New'}));
    expect(failures, isEmpty);
    expect(writer.written.keys, [storage.audioFile('hash1.mp3').path]);
    expect(writer.written.values.single.album, 'New');
    expect(writer.written.values.single.title, 'A');
    expect(repo.updatedTags, [
      {1: const TrackTags(title: 'A', album: 'New')},
    ]);
  });

  test('a failed write leaves its row unchanged and is reported', () async {
    writer.failing[storage.audioFile('hash2.mp3').path] = 'read-only file';
    final failures = await saver.save([
      a,
      b,
    ], const TagEdit({TagField.album: 'New'}));
    expect(failures, hasLength(1));
    expect(failures.single.track.id, 2);
    expect(failures.single.message, 'read-only file');
    expect(repo.updatedTags.single.keys, [1]);
  });

  test('a write that throws is reported too', () async {
    writer.throwing = true;
    final failures = await saver.save([
      a,
    ], const TagEdit({TagField.album: 'X'}));
    expect(failures.single.track.id, 1);
    expect(repo.updatedTags, isEmpty);
  });

  test('unchanged songs are not written', () async {
    final failures = await saver.save([
      a,
    ], const TagEdit({TagField.album: 'Old'}));
    expect(failures, isEmpty);
    expect(writer.written, isEmpty);
    expect(repo.updatedTags, isEmpty);
  });

  test('rows of one save are updated in one call', () async {
    await saver.save([a, b], const TagEdit({TagField.genre: 'Folk'}));
    expect(repo.updatedTags, hasLength(1));
    expect(repo.updatedTags.single.keys, [1, 2]);
  });
}
