import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/import/audio_file_picker.dart';
import 'package:owntune/import/import_controller.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/song_sort.dart';
import 'package:owntune/player/audio_engine.dart';
import 'package:owntune/player/player_snapshot.dart';
import 'package:owntune/settings/settings.dart';
import 'package:owntune/src/rust/api/library.dart';
import 'package:owntune/src/rust/api/metadata.dart';

/// Opened by `startUp()`; `main` overrides it with the real instance.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider is set in main()'),
);

/// Opened by `startUp()`; `main` overrides it with the real instance.
final storageProvider = Provider<LibraryStorage>(
  (ref) => throw UnimplementedError('storageProvider is set in main()'),
);

final trackRepositoryProvider = Provider<TrackRepository>(
  (ref) =>
      TrackRepository(ref.watch(databaseProvider), ref.watch(storageProvider)),
);

/// All tracks, unsorted; updates live while an import runs.
final tracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(trackRepositoryProvider).watchAll(),
);

/// Songs, albums and artists derived from [tracksProvider].
final libraryProvider = Provider<AsyncValue<Library>>(
  (ref) => ref.watch(tracksProvider).whenData(Library.from),
);

/// The library's songs in the order chosen in the settings.
final sortedSongsProvider = Provider<AsyncValue<List<Track>>>((ref) {
  final settings = ref.watch(settingsProvider);
  return ref
      .watch(libraryProvider)
      .whenData(
        (library) => sortSongs(
          library.tracks,
          settings.songSort,
          descending: settings.songSortDescending,
        ),
      );
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

/// The settings loaded by `startUp()`; `main` overrides it.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => AppSettings.defaults,
);

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  /// Applies [settings] immediately and persists them.
  Future<void> set(AppSettings settings) async {
    state = settings;
    await ref.read(settingsRepositoryProvider).save(settings);
  }
}

/// The one importer of the app; [ImportController] makes sure it never runs
/// twice at the same time.
final importerProvider = Provider<Importer>(
  (ref) => Importer(
    repo: ref.watch(trackRepositoryProvider),
    storage: ref.watch(storageProvider),
    read: (p) => readTrack(path: p),
    supportedExtensions: supportedFormats().toSet(),
  ),
);

final filePickerProvider = Provider<AudioFilePicker>(
  (ref) => const AudioFilePicker(),
);

final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);

/// The one audio engine of the app; tests override it with a fake.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = JustAudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Where the player's state is saved for the next start.
final playerStateStoreProvider = Provider<PlayerStateStore>(
  (ref) => DbPlayerStateStore(ref.watch(databaseProvider)),
);

/// The player state saved by the last run, loaded by `startUp()`; `main`
/// overrides it.
final initialPlayerSnapshotProvider = Provider<PlayerSnapshot?>((ref) => null);
