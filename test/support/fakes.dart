import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/play_repository.dart';
import 'package:owntune/data/playlist_repository.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/edit/cover_picker.dart';
import 'package:owntune/edit/tag_saver.dart';
import 'package:owntune/edit/track_tags.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/home/stats_repository.dart';
import 'package:owntune/import/audio_file_picker.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/player/audio_engine.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_link.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/soundcloud/client_id_store.dart';
import 'package:owntune/download/cover_image.dart';
import 'package:owntune/download/download_controller.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/player/player_snapshot.dart';
import 'package:owntune/player/system_controls.dart';
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
  String? sourceKey,
  DateTime? likedAt,
  int playCount = 0,
  DateTime? lastPlayedAt,
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
  playCount: playCount,
  lastPlayedAt: lastPlayedAt,
  sourceKey: sourceKey,
  likedAt: likedAt,
);

const summary47 = ImportSummary(
  added: 47,
  duplicates: 2,
  unsupported: ['evening-walk.ogg'],
  albums: 8,
  artists: 7,
);

/// An importer whose runs are completed by the test. Like the real one, a
/// call made while another runs waits for it; [calls] lists runs that have
/// started.
class FakeImporter implements Importer {
  final calls = <List<String>>[];
  final sourceKeys = <Map<String, String>>[];
  Completer<ImportSummary>? _pending;
  void Function(ImportProgress)? _onProgress;
  final _waiting = <void Function()>[];

  bool get isRunning => _pending != null && !_pending!.isCompleted;

  @override
  Future<ImportSummary> importFiles(
    List<String> paths, {
    void Function(ImportProgress)? onProgress,
    Map<String, String> sourceKeys = const {},
  }) {
    final result = Completer<ImportSummary>();
    void start() {
      calls.add(paths);
      this.sourceKeys.add(sourceKeys);
      _onProgress = onProgress;
      _pending = Completer();
      _pending!.future.then(result.complete, onError: result.completeError);
      _pending!.future.whenComplete(() {
        if (_waiting.isNotEmpty) _waiting.removeAt(0)();
      }).ignore();
    }

    if (isRunning) {
      _waiting.add(start);
    } else {
      start();
    }
    return result.future;
  }

  void progress(int done, int total, String name) => _onProgress?.call(
    ImportProgress(done: done, total: total, currentName: name),
  );

  void finish(ImportSummary summary) => _pending!.complete(summary);

  void fail(Object error) => _pending!.completeError(error);
}

/// Records `delete` calls and returns fixed library stats; other members are
/// unused in widget tests.
/// Records written tags by file path; paths in [failing] return their
/// message instead, and [throwing] makes every write throw.
class FakeTagWriter {
  final written = <String, TrackTags>{};

  /// The cover change of every write that succeeded, by path.
  final covers = <String, CoverEdit>{};
  final failing = <String, String>{};
  var throwing = false;

  Future<String?> call(String path, TrackTags tags, CoverEdit cover) async {
    if (throwing) throw const FileSystemException('disk gone');
    final error = failing[path];
    if (error != null) return error;
    written[path] = tags;
    covers[path] = cover;
    return null;
  }
}

class FakeTrackRepository implements TrackRepository {
  FakeTrackRepository({this.songCount = 0, this.bytes = 0, this.deleteError});

  final int songCount;
  final int bytes;

  /// Thrown by [delete] when set.
  final Object? deleteError;
  final deleted = <int>[];

  /// Ids passed to [markPlayed], in order.
  final played = <int>[];

  /// Every [updateTags] call, in order.
  final updatedTags = <Map<int, TrackTags>>[];

  /// The `coverFiles` of every [updateTags] call, in order.
  final updatedCovers = <Map<int, String?>>[];

  /// Cover file names [isCoverReferenced] reports as still in use.
  final referencedCovers = <String>{};

  @override
  Future<void> updateTags(
    Map<int, TrackTags> byId, {
    Map<int, String?> coverFiles = const {},
  }) async {
    updatedTags.add(byId);
    updatedCovers.add(coverFiles);
  }

  /// Every [setLiked] call, in order.
  final likeCalls = <({List<int> ids, bool liked})>[];

  @override
  Future<void> setLiked(Iterable<int> ids, {required bool liked}) async {
    likeCalls.add((ids: ids.toList(), liked: liked));
  }

  @override
  Future<bool> isCoverReferenced(String cover) async =>
      referencedCovers.contains(cover);

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

/// Home queries with fixed lists; set [recent] and [top] before pumping.
class FakeHomeRepository implements HomeRepository {
  List<RecentSource> recent = [];
  List<TrackPlayCount> top = [];

  /// The `since` of every call, in order.
  final recentSince = <DateTime>[];
  final topSince = <DateTime>[];

  @override
  Stream<List<RecentSource>> watchRecentSources({
    required DateTime since,
    int limit = 20,
  }) {
    recentSince.add(since);
    return Stream.value(recent);
  }

  @override
  Stream<List<TrackPlayCount>> watchTopTracks({
    required DateTime since,
    int limit = 50,
  }) {
    topSince.add(since);
    return Stream.value(top);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stats queries with fixed results; set the fields before pumping.
class FakeStatsRepository implements StatsRepository {
  List<TrackTotal> totals = [];
  List<ListeningBucket> buckets = [];
  List<int> hourly = List.filled(24, 0);
  Map<int, ({DateTime first, int counted})> history = {};
  DateTime? firstPlayAt;

  /// The rows of every comparison day.
  List<StatsPlayRow> dayRows = [];

  /// The counted plays in the whole history; null: the plays of [buckets].
  int? countedPlays;

  /// The arguments of every call, in order.
  final totalsRanges = <({DateTime from, DateTime to})>[];
  final bucketRanges = <({DateTime from, DateTime to, StatsBucket bucket})>[];
  final hourlyRanges = <({DateTime from, DateTime to})>[];
  final rowDays = <DateTime>[];

  @override
  Stream<List<TrackTotal>> watchTrackTotals({
    required DateTime from,
    required DateTime to,
  }) {
    totalsRanges.add((from: from, to: to));
    return Stream.value(totals);
  }

  @override
  Stream<List<ListeningBucket>> watchListeningBuckets({
    required DateTime from,
    required DateTime to,
    required StatsBucket bucket,
    bool countedOnly = false,
  }) {
    bucketRanges.add((from: from, to: to, bucket: bucket));
    return Stream.value(buckets);
  }

  @override
  Stream<List<StatsPlayRow>> watchRowsOfDay({required DateTime day}) {
    rowDays.add(day);
    return Stream.value(dayRows);
  }

  @override
  Stream<int> watchCountedPlays() => Stream.value(
    countedPlays ?? buckets.fold<int>(0, (sum, b) => sum + b.plays),
  );

  @override
  Stream<List<int>> watchHourly({
    required DateTime from,
    required DateTime to,
  }) {
    hourlyRanges.add((from: from, to: to));
    return Stream.value(hourly);
  }

  @override
  Stream<Map<int, ({DateTime first, int counted})>> watchTrackHistory() =>
      Stream.value(history);

  @override
  Stream<DateTime?> watchFirstPlayAt() => Stream.value(firstPlayAt);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Keeps the play history in memory; ids start at 1.
class FakePlayRepository implements PlayRepository {
  final rows =
      <
        int,
        ({
          int trackId,
          DateTime startedAt,
          int listenedMs,
          bool counted,
          String? sourceKind,
          String? sourceKey,
        })
      >{};

  /// When set, [insert] and [update] throw it.
  Object? error;

  @override
  Future<int> insert({
    required int trackId,
    required DateTime startedAt,
    required int listenedMs,
    required bool counted,
    String? sourceKind,
    String? sourceKey,
  }) async {
    if (error != null) throw error!;
    final id = rows.length + 1;
    rows[id] = (
      trackId: trackId,
      startedAt: startedAt,
      listenedMs: listenedMs,
      counted: counted,
      sourceKind: sourceKind,
      sourceKey: sourceKey,
    );
    return id;
  }

  @override
  Future<void> update(
    int id, {
    required int listenedMs,
    required bool counted,
  }) async {
    if (error != null) throw error!;
    final row = rows[id]!;
    rows[id] = (
      trackId: row.trackId,
      startedAt: row.startedAt,
      listenedMs: listenedMs,
      counted: counted,
      sourceKind: row.sourceKind,
      sourceKey: row.sourceKey,
    );
  }

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

/// Keeps the last saved player state in memory.
class FakePlayerStateStore implements PlayerStateStore {
  FakePlayerStateStore([this.saved]);

  PlayerSnapshot? saved;
  var saves = 0;

  @override
  Future<PlayerSnapshot?> load() async => saved;

  @override
  Future<void> save(PlayerSnapshot? snapshot) async {
    saves++;
    saved = snapshot;
  }
}

/// Records what would show on the lock screen; the test sends commands
/// through [commands].
class FakeSystemControls implements SystemControls {
  SystemCommands? commands;
  final shown = <NowPlaying?>[];

  @override
  void connect(SystemCommands commands) => this.commands = commands;

  @override
  void show(NowPlaying? now) => shown.add(now);
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

/// Returns fixed bytes for each pick (null = cancelled) and counts picks.
class FakeCoverPicker implements CoverPicker {
  FakeCoverPicker({this.photo, this.file});

  Uint8List? photo;
  Uint8List? file;
  var photos = 0;
  var files = 0;

  @override
  Future<Uint8List?> pickPhoto() async {
    photos++;
    return photo;
  }

  @override
  Future<Uint8List?> pickFile() async {
    files++;
    return file;
  }
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
  FakeTagWriter? tagWriter,
  FakeTrackRepository? editRepo,
  Map<OnlineSourceId, OnlineSource>? onlineSources,
  FakeDownloadController? downloads,
  FakeCoverPicker? coverPicker,
  PlaylistRepository? playlists,
  FakePlayRepository? plays,
  FakeHomeRepository? home,
  FakeStatsRepository? stats,
  List<Override> overrides = const [],
  List<ProviderObserver>? observers,
}) async {
  final libraryStorage =
      storage ?? LibraryStorage(Directory('/nonexistent/owntune'));
  var playlistRepo = playlists;
  if (playlistRepo == null) {
    // Streams close synchronously so cancelled queries leave no timer.
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    playlistRepo = PlaylistRepository(
      db,
      libraryStorage,
      hash: (_) => 'playlistcover',
    );
  }
  await t.pumpWidget(
    ProviderScope(
      observers: observers,
      overrides: [
        playlistRepositoryProvider.overrideWithValue(playlistRepo),
        playRepositoryProvider.overrideWithValue(plays ?? FakePlayRepository()),
        homeRepositoryProvider.overrideWithValue(home ?? FakeHomeRepository()),
        statsRepositoryProvider.overrideWithValue(
          stats ?? FakeStatsRepository(),
        ),
        tracksProvider.overrideWith(
          (ref) => songsStream ?? Stream.value(songs),
        ),
        storageProvider.overrideWithValue(libraryStorage),
        tagSaverProvider.overrideWithValue(
          TagSaver(
            write: (tagWriter ?? FakeTagWriter()).call,
            storage: libraryStorage,
            repo: editRepo ?? FakeTrackRepository(),
            hash: (_) => 'coverhash',
          ),
        ),
        importerProvider.overrideWithValue(importer ?? FakeImporter()),
        filePickerProvider.overrideWithValue(picker ?? FakePicker()),
        coverPickerProvider.overrideWithValue(coverPicker ?? FakeCoverPicker()),
        audioEngineProvider.overrideWithValue(engine ?? FakeAudioEngine()),
        playerStateStoreProvider.overrideWithValue(FakePlayerStateStore()),
        onlineSourcesProvider.overrideWithValue(
          onlineSources ??
              {
                for (final id in OnlineSourceId.values)
                  id: FakeOnlineSource(id),
              },
        ),
        downloadControllerProvider.overrideWith(
          () => downloads ?? FakeDownloadController(),
        ),
        ...overrides,
      ],
      child: OwntuneApp(onOpenSettings: onOpenSettings),
    ),
  );
  await t.pump();
  await t.pump();
}

/// Taps the Library tab in the tab bar; the app opens on Home.
Future<void> openLibraryTab(WidgetTester t) async {
  await t.tap(
    find.descendant(
      of: find.byType(BackdropFilter),
      matching: find.text('Library'),
    ),
  );
  await t.pumpAndSettle();
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

/// One `postJson` call seen by [FakeHttpTransport].
typedef PostCall = ({
  Uri url,
  Map<String, Object?> body,
  Map<String, String> headers,
});

/// Answers requests from handlers set by the test and records `postJson`
/// calls.
class FakeHttpTransport implements HttpTransport {
  FakeHttpTransport({this.onPost, this.onGet, this.onFinalUrl});

  Map<String, Object?> Function(Uri url, Map<String, Object?> body)? onPost;
  Future<HttpBody> Function(Uri url, Map<String, String> headers)? onGet;

  /// Where a URL redirects to; the default is no redirect.
  Future<Uri> Function(Uri url)? onFinalUrl;
  final posts = <PostCall>[];
  final gets = <Uri>[];
  final finalUrls = <Uri>[];

  @override
  Future<Map<String, Object?>> postJson(
    Uri url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
    String service = 'YouTube',
  }) async {
    posts.add((url: url, body: body, headers: headers));
    return onPost!(url, body);
  }

  @override
  Future<Map<String, Object?>> getJson(
    Uri url, {
    Map<String, String> headers = const {},
    required String service,
  }) async {
    gets.add(url);
    final res = await onGet!(url, headers);
    final text = await utf8.decoder.bind(res.stream).join();
    if (res.statusCode != 200) throw HttpStatusError(service, res.statusCode);
    return jsonDecode(text) as Map<String, Object?>;
  }

  @override
  Future<HttpBody> get(Uri url, {Map<String, String> headers = const {}}) {
    gets.add(url);
    return onGet!(url, headers);
  }

  @override
  Future<Uri> finalUrl(Uri url) async {
    finalUrls.add(url);
    return onFinalUrl == null ? url : onFinalUrl!(url);
  }
}

/// [SoundcloudClientIdStore] in memory.
class MemorySoundcloudClientIdStore implements SoundcloudClientIdStore {
  MemorySoundcloudClientIdStore([this.id]);

  String? id;

  @override
  Future<String?> read() async => id;

  @override
  Future<void> write(String id) async => this.id = id;
}

/// A search result for tests. SoundCloud results get `soundcloud:` keys and
/// carry their genre and year in the tags; YouTube ones get `youtube:` keys.
OnlineResult onlineResult(
  String id, {
  OnlineSourceId source = OnlineSourceId.ytmusic,
  String title = 'Numb',
  String? artist = 'Linkin Park',
  String? album = 'Meteora',
  String? channel,
  String? subtitle,
  String? genre,
  int? year,
  OnlineAvailability availability = OnlineAvailability.available,
  int? kbps,
}) {
  final soundcloud = source == OnlineSourceId.soundcloud;
  return OnlineResult(
    sourceKey: '${soundcloud ? 'soundcloud' : 'youtube'}:$id',
    id: id,
    source: source,
    title: title,
    subtitle: subtitle ?? [?artist, ?album].join(' · '),
    duration: const Duration(minutes: 3, seconds: 8),
    thumbnail: Uri.parse('https://example.invalid/thumb/$id.jpg'),
    coverUrl: Uri.parse('https://example.invalid/cover/$id.jpg'),
    squareCover: source != OnlineSourceId.youtube,
    channel: channel,
    tags: source == OnlineSourceId.youtube
        ? const TrackTags()
        : TrackTags(
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            year: year,
          ),
    availability: availability,
    kbps: kbps,
  );
}

/// A source with canned results; [resolve] answers from [streams] (or
/// throws [resolveError]) and records the ids it was asked for.
class FakeOnlineSource implements OnlineSource {
  FakeOnlineSource(this.id, {this.results = const []});

  @override
  final OnlineSourceId id;
  List<OnlineResult> results;
  Object? searchError;
  final searches = <String>[];
  final streams = <String, ResolvedStream>{};
  Object? resolveError;
  final resolved = <String>[];

  /// When set, [search] waits for it (to see the loading state).
  Completer<void>? searchGate;

  /// The links [lookup] was asked for.
  final lookups = <OnlineLink>[];

  /// Canned answers of [lookup], keyed by video id (YouTube) or by the link's
  /// URL string (SoundCloud); any other link gets a default result.
  final linkResults = <String, OnlineResult>{};
  Object? lookupError;

  /// When set, [lookup] waits for it.
  Completer<void>? lookupGate;

  @override
  Future<OnlineResult> lookup(OnlineLink link) async {
    lookups.add(link);
    await lookupGate?.future;
    if (lookupError case final e?) throw e;
    return switch (link) {
      YoutubeLink(:final videoId) =>
        linkResults[videoId] ??
            onlineResult(videoId, source: OnlineSourceId.youtube),
      SoundcloudLink(:final url) =>
        linkResults['$url'] ??
            onlineResult(
              url.pathSegments.last,
              source: OnlineSourceId.soundcloud,
            ),
      UnsupportedLink(:final message) => throw OnlineError(message),
    };
  }

  @override
  Future<List<OnlineResult>> search(String query) async {
    searches.add(query);
    await searchGate?.future;
    if (searchError case final e?) throw e;
    return results;
  }

  @override
  Future<ResolvedStream> resolve(OnlineResult result) async {
    resolved.add(result.id);
    if (resolveError case final e?) throw e;
    return streams[result.id] ??
        RangedStream(
          url: Uri.parse('https://example.invalid/audio/${result.id}'),
          contentLength: 4,
          extension: 'm4a',
          bitrate: 128000,
        );
  }
}

/// Records what the downloader writes into files; [error] makes it fail.
class FakeDownloadTagWriter {
  final calls = <({String path, TrackTags tags, CoverBytes? cover})>[];
  String? error;

  Future<String?> call(String path, TrackTags tags, CoverBytes? cover) async {
    calls.add((path: path, tags: tags, cover: cover));
    return error;
  }
}

/// Serves [bytes] for `range=<start>-<end>` GETs, like googlevideo.
Future<HttpBody> Function(Uri, Map<String, String>) serveRanges(
  List<int> bytes, {
  int Function(int callIndex)? status,
  int? maxPerResponse,
}) {
  var calls = 0;
  return (url, headers) async {
    final i = calls++;
    final code = status?.call(i) ?? 200;
    if (code != 200) return HttpBody(code, const Stream.empty());
    final [start, end] = url.queryParameters['range']!
        .split('-')
        .map(int.parse)
        .toList();
    var last = end + 1 > bytes.length ? bytes.length : end + 1;
    if (maxPerResponse != null && last - start > maxPerResponse) {
      last = start + maxPerResponse;
    }
    return HttpBody(200, Stream.value(bytes.sublist(start, last)));
  };
}

/// Answers a GET by `url.path` with the bytes in [byPath], or 404 for a path
/// that is not in it; [status] can replace the code for a path.
Future<HttpBody> Function(Uri, Map<String, String>) serveSegments(
  Map<String, List<int>> byPath, {
  int Function(String path)? status,
}) {
  return (url, headers) async {
    final data = byPath[url.path];
    final code = data == null ? 404 : status?.call(url.path) ?? 200;
    if (data == null || code != 200) {
      return HttpBody(code, const Stream.empty());
    }
    return HttpBody(200, Stream.value(data));
  };
}

/// A download queue whose state the test sets; records the calls.
class FakeDownloadController extends DownloadController {
  FakeDownloadController([this.initial = const []]);

  final List<DownloadJob> initial;
  final enqueued = <({OnlineResult result, TrackTags tags})>[];
  final cancelled = <int>[];
  final retried = <int>[];
  var cleared = 0;

  @override
  List<DownloadJob> build() => initial;

  set jobs(List<DownloadJob> jobs) => state = jobs;

  @override
  void enqueue(OnlineResult result, TrackTags tags) =>
      enqueued.add((result: result, tags: tags));

  @override
  void cancel(int id) => cancelled.add(id);

  @override
  void retry(int id) => retried.add(id);

  @override
  void clearFinished() => cleared++;
}

/// A job for tests.
DownloadJob downloadJob(
  int id,
  String resultId, {
  DownloadPhase phase = DownloadPhase.waiting,
  int received = 0,
  int total = 0,
  String? error,
  String title = 'Numb',
  OnlineSourceId source = OnlineSourceId.ytmusic,
}) => DownloadJob(
  id: id,
  result: onlineResult(resultId, title: title, source: source),
  tags: TrackTags(title: title, artist: 'Linkin Park'),
  phase: phase,
  received: received,
  total: total,
  error: error,
);
