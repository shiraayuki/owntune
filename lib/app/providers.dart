import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/play_repository.dart';
import 'package:owntune/data/playlist_repository.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/youtube/youtube_sources.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/download/download_controller.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/edit/cover_picker.dart';
import 'package:owntune/edit/tag_saver.dart';
import 'package:owntune/edit/track_tags.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/home/stats_repository.dart';
import 'package:owntune/import/audio_file_picker.dart';
import 'package:owntune/import/import_controller.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/library/song_selection.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/song_sort.dart';
import 'package:owntune/player/audio_engine.dart';
import 'package:owntune/player/player_snapshot.dart';
import 'package:owntune/playlists/playlist_view.dart';
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

/// The source keys (e.g. `youtube:<id>`) of all downloaded tracks; empty
/// while the library loads.
final librarySourceKeysProvider = Provider<Set<String>>(
  (ref) => {
    for (final t in ref.watch(tracksProvider).value ?? const <Track>[])
      ?t.sourceKey,
  },
);

/// Songs, albums and artists derived from [tracksProvider].
final libraryProvider = Provider<AsyncValue<Library>>(
  (ref) => ref.watch(tracksProvider).whenData(Library.from),
);

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => PlaylistRepository(
    ref.watch(databaseProvider),
    ref.watch(storageProvider),
    hash: (data) => hashBytes(data: data),
  ),
);

final playRepositoryProvider = Provider<PlayRepository>(
  (ref) => PlayRepository(ref.watch(databaseProvider)),
);

/// The current time; tests override it.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ref.watch(databaseProvider)),
);

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(databaseProvider)),
);

final _playlistRowsProvider = StreamProvider<List<Playlist>>(
  (ref) => ref.watch(playlistRepositoryProvider).watchPlaylists(),
);

final _playlistEntryRowsProvider = StreamProvider<List<PlaylistEntry>>(
  (ref) => ref.watch(playlistRepositoryProvider).watchEntries(),
);

/// The playlists with their songs, newest first; entries of songs deleted
/// from the library are left out.
final playlistsProvider = Provider<AsyncValue<List<PlaylistView>>>((ref) {
  final playlists = ref.watch(_playlistRowsProvider);
  final entries = ref.watch(_playlistEntryRowsProvider);
  final tracks = ref.watch(tracksProvider);
  for (final source in [playlists, entries, tracks]) {
    if (source.hasError) {
      return AsyncError(source.error!, source.stackTrace ?? StackTrace.empty);
    }
  }
  if (!playlists.hasValue || !entries.hasValue || !tracks.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData(
    resolvePlaylists(playlists.value!, entries.value!, tracks.value!),
  );
});

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

  /// Puts [query] first in the recent Search Online queries (trimmed, no
  /// case-insensitive duplicates, at most [AppSettings.maxRecentSearches]).
  Future<void> addRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final recent = [
      q,
      for (final r in state.recentSearches)
        if (r.toLowerCase() != q.toLowerCase()) r,
    ].take(AppSettings.maxRecentSearches).toList();
    await set(state.copyWith(recentSearches: recent));
  }

  Future<void> removeRecentSearch(String query) => set(
    state.copyWith(
      recentSearches: [
        for (final r in state.recentSearches)
          if (r != query) r,
      ],
    ),
  );
}

/// The one importer of the app. It queues its calls itself, so Import Music
/// ([ImportController]) and downloads never import at the same time.
final importerProvider = Provider<Importer>(
  (ref) => Importer(
    repo: ref.watch(trackRepositoryProvider),
    storage: ref.watch(storageProvider),
    read: (p) => readTrack(path: p),
    supportedExtensions: supportedFormats().toSet(),
  ),
);

/// Saves edited song tags; tests override it with a fake writer.
final tagSaverProvider = Provider<TagSaver>(
  (ref) => TagSaver(
    repo: ref.watch(trackRepositoryProvider),
    storage: ref.watch(storageProvider),
    write: (path, t, cover) => writeTags(
      path: path,
      tags: TagValues(
        title: t.title,
        artist: t.artist,
        album: t.album,
        albumArtist: t.albumArtist,
        genre: t.genre,
        trackNumber: t.trackNumber,
        discNumber: t.discNumber,
        year: t.year,
        cover: switch (cover) {
          CoverSet(:final data, :final mime) => CoverInput(
            data: data,
            mime: mime,
          ),
          _ => null,
        },
        removeCover: cover is CoverRemove,
      ),
    ),
    hash: (data) => hashBytes(data: data),
  ),
);

/// Picks cover images; tests override it with a fake.
final coverPickerProvider = Provider<CoverPicker>((ref) => const CoverPicker());

/// Multi-select in Songs (null = off).
final songSelectionProvider = NotifierProvider<SongSelection, Set<int>?>(
  SongSelection.new,
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

/// The app's HTTP client for online sources and downloads; tests override
/// it.
final httpTransportProvider = Provider<HttpTransport>(
  (ref) => IoHttpTransport(),
);

/// The searchable online sources by id.
final onlineSourcesProvider = Provider<Map<OnlineSourceId, OnlineSource>>((
  ref,
) {
  final youtube = YoutubeSources(ref.watch(httpTransportProvider));
  return {
    OnlineSourceId.ytmusic: youtube.music,
    OnlineSourceId.youtube: youtube.video,
  };
});

/// The app-wide download queue.
final downloadControllerProvider =
    NotifierProvider<DownloadController, List<DownloadJob>>(
      DownloadController.new,
    );

/// Writes tags and cover into a downloaded file (Rust); tests override it.
final downloadTagWriterProvider = Provider<WriteDownloadTags>(
  (ref) =>
      (path, t, cover) => writeTags(
        path: path,
        tags: TagValues(
          title: t.title,
          artist: t.artist,
          album: t.album,
          albumArtist: t.albumArtist,
          genre: t.genre,
          trackNumber: t.trackNumber,
          discNumber: t.discNumber,
          year: t.year,
          cover: cover == null
              ? null
              : CoverInput(data: cover.data, mime: cover.mime),
          removeCover: false,
        ),
      ),
);

/// Where downloads keep their files until the import; tests override it.
final downloadDirProvider = Provider<Future<Directory> Function()>(
  (ref) => defaultDownloadDir,
);
