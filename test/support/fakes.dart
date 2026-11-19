import 'dart:async';
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/import/audio_file_picker.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/player/audio_engine.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:owntune/settings/settings.dart';

Track track(
  int id, {
  String? title,
  String? artist,
  String? album,
  String? albumArtist,
  int? trackNumber,
  int? discNumber,
  int? year,
  String? genre,
  int durationMs = 1000,
  DateTime? addedAt,
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
  albumArtist: albumArtist,
  trackNumber: trackNumber,
  discNumber: discNumber,
  year: year,
  genre: genre,
  durationMs: durationMs,
  coverFile: cover,
  addedAt: addedAt ?? DateTime(2026, 11, 18),
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

/// Records `delete` calls and returns fixed library stats; other members are
/// unused in widget tests.
class FakeTrackRepository implements TrackRepository {
  FakeTrackRepository({this.songCount = 0, this.bytes = 0, this.deleteError});

  final int songCount;
  final int bytes;

  /// Thrown by [delete] when set.
  final Object? deleteError;
  final deleted = <int>[];

  /// Ids passed to [markPlayed], in order.
  final played = <int>[];

  @override
  Future<void> markPlayed(int id) async => played.add(id);

  @override
  Future<void> delete(int id) async {
    if (deleteError != null) throw deleteError!;
    deleted.add(id);
  }

  @override
  Future<int> count() async => songCount;

  @override
  Future<int> storageBytes() async => bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records every saved [AppSettings].
class FakeSettingsRepository implements SettingsRepository {
  final saved = <AppSettings>[];

  @override
  Future<void> save(AppSettings s) async => saved.add(s);

  @override
  Future<AppSettings> load() async => AppSettings.defaults;
}

/// An audio engine without audio: records what it was told and lets the
/// test emit positions, completion and errors.
class FakeAudioEngine implements AudioEngine {
  /// Base names of the loaded files, in load order.
  final loaded = <String>[];
  var playing = false;
  Duration? lastSeek;
  var unloads = 0;

  /// Base names whose load throws.
  final failing = <String>{};

  /// When set, [load] waits for it before it returns.
  Completer<void>? holdLoad;

  final _position = StreamController<Duration>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  String? get current => loaded.isEmpty ? null : loaded.last;

  @override
  Future<void> load(File file) async {
    final name = p.basename(file.path);
    loaded.add(name);
    final hold = holdLoad;
    if (hold != null) await hold.future;
    if (failing.contains(name)) throw StateError('cannot decode $name');
  }

  @override
  // Like just_audio, the play state stream also reports changes the app
  // asked for.
  @override
  Future<void> play() async => _setPlaying(true);

  @override
  Future<void> pause() async => _setPlaying(false);

  void _setPlaying(bool value) {
    if (playing == value) return;
    playing = value;
    _playing.add(value);
  }

  @override
  Stream<bool> get playingChanges => _playing.stream;

  /// The engine changes its play state on its own (e.g. a phone call).
  void emitPlaying(bool value) => _setPlaying(value);

  @override
  Future<void> seek(Duration position) async => lastSeek = position;

  @override
  Future<void> unload() async {
    _setPlaying(false);
    unloads++;
  }

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Stream<Object> get errors => _errors.stream;

  void emitPosition(Duration d) => _position.add(d);

  void complete() => _completed.add(null);

  void emitError(Object e) => _errors.add(e);

  @override
  Future<void> dispose() async {}
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
  Stream<List<Track>>? songsStream,
  FakeImporter? importer,
  FakePicker? picker,
  FakeAudioEngine? engine,
  LibraryStorage? storage,
  void Function(BuildContext)? onOpenSettings,
  List<Override> overrides = const [],
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        tracksProvider.overrideWith(
          (ref) => songsStream ?? Stream.value(songs),
        ),
        storageProvider.overrideWithValue(
          storage ?? LibraryStorage(Directory('/nonexistent/owntune')),
        ),
        importerProvider.overrideWithValue(importer ?? FakeImporter()),
        filePickerProvider.overrideWithValue(picker ?? FakePicker()),
        audioEngineProvider.overrideWithValue(engine ?? FakeAudioEngine()),
        ...overrides,
      ],
      child: OwntuneApp(onOpenSettings: onOpenSettings),
    ),
  );
  await t.pump();
  await t.pump();
}

/// Taps the back button of the current screen's [NavRow].
Future<void> tapBack(WidgetTester t) async {
  await t.tap(
    find.descendant(
      of: find.byType(NavRow),
      matching: find.byIcon(CupertinoIcons.chevron_left),
    ),
  );
  await t.pumpAndSettle();
}

/// Opens the "+" menu and chooses Import Music.
Future<void> tapImport(WidgetTester t) async {
  await t.tap(find.byKey(const Key('import-button')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('menu-import')));
  await t.pumpAndSettle();
}
