import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/import/audio_file_picker.dart';
import 'package:owntune/import/importer.dart';
import 'package:material_ui/material_ui.dart';

Track track(
  int id, {
  String? title,
  String? artist,
  String? album,
  String? originalName,
  String? cover,
}) => Track(
  id: id,
  fileName: 'hash$id.mp3',
  originalName: originalName ?? '${title ?? 'track$id'}.mp3',
  contentHash: 'hash$id',
  title: title,
  artist: artist,
  album: album,
  durationMs: 1000,
  coverFile: cover,
  addedAt: DateTime(2026, 11, 18),
  playCount: 0,
);

const summary47 = ImportSummary(
  added: 47,
  duplicates: 2,
  unsupported: ['evening-walk.ogg'],
  albums: 8,
  artists: 7,
);

/// An importer whose runs are completed by the test.
class FakeImporter implements Importer {
  final calls = <List<String>>[];
  Completer<ImportSummary>? _pending;
  void Function(ImportProgress)? _onProgress;

  bool get isRunning => _pending != null && !_pending!.isCompleted;

  @override
  Future<ImportSummary> importFiles(
    List<String> paths, {
    void Function(ImportProgress)? onProgress,
  }) {
    if (isRunning) throw StateError('An import is already running');
    calls.add(paths);
    _onProgress = onProgress;
    _pending = Completer();
    return _pending!.future;
  }

  void progress(int done, int total, String name) => _onProgress?.call(
    ImportProgress(done: done, total: total, currentName: name),
  );

  void finish(ImportSummary summary) => _pending!.complete(summary);

  void fail(Object error) => _pending!.completeError(error);
}

class FakePicker implements AudioFilePicker {
  FakePicker([this.result = const []]);

  List<String> result;
  var picks = 0;
  var cleanups = 0;

  @override
  Future<List<String>> pick() async {
    picks++;
    return result;
  }

  @override
  Future<void> clearTemporaryFiles() async => cleanups++;
}

/// Pumps the whole app with fake data; no database and no Rust.
Future<void> pumpApp(
  WidgetTester t, {
  List<Track> songs = const [],
  FakeImporter? importer,
  FakePicker? picker,
  LibraryStorage? storage,
  void Function(BuildContext)? onOpenSettings,
  List<Override> overrides = const [],
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        songsProvider.overrideWith((ref) => Stream.value(songs)),
        storageProvider.overrideWithValue(
          storage ?? LibraryStorage(Directory('/nonexistent/owntune')),
        ),
        importerProvider.overrideWithValue(importer ?? FakeImporter()),
        filePickerProvider.overrideWithValue(picker ?? FakePicker()),
        ...overrides,
      ],
      child: OwntuneApp(onOpenSettings: onOpenSettings),
    ),
  );
  await t.pump();
  await t.pump();
}
