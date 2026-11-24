import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/player/audio_engine.dart';
import 'package:owntune/player/audio_setup.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/queue_source.dart';
import 'package:owntune/src/rust/api/library.dart';
import 'package:owntune/src/rust/api/metadata.dart';
import 'package:owntune/src/rust/frb_generated.dart';

import 'support/fixtures.dart';

/// A mono 16-bit PCM WAV with a quiet tone, [seconds] long. The fixtures are
/// only one second long, which is too short to be sure of 1 s of heard time.
Uint8List _tone(int seconds) {
  const rate = 8000;
  final samples = rate * seconds;
  final data = ByteData(44 + samples * 2);
  void tag(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    final v = (sin(2 * pi * 440 * i / rate) * 3000).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LibraryStorage storage;
  late AppDatabase db;
  late TrackRepository tracks;

  setUpAll(() async {
    await RustLib.init();
    await initAudio();
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('owntune_liked_it');
    storage = LibraryStorage(Directory('${tmp.path}/library'));
    await storage.ensure();
    db = AppDatabase(NativeDatabase(File('${tmp.path}/owntune.sqlite')));
    tracks = TrackRepository(db, storage);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> import(List<String> paths) => Importer(
    repo: tracks,
    storage: storage,
    read: (p) => readTrack(path: p),
    supportedExtensions: supportedFormats().toSet(),
  ).importFiles(paths);

  testWidgets('like and unlike against the real database', (t) async {
    await import([
      for (final name in ['tagged.mp3', 'tagged.m4a'])
        File('${fixturesDir().path}/$name').copySync('${tmp.path}/$name').path,
    ]);
    final imported = await tracks.watchAll().first;
    expect(imported, hasLength(2));
    expect(imported.every((x) => x.likedAt == null), isTrue);

    final first = imported.first.id;
    await tracks.setLiked([first], liked: true);
    var all = await tracks.watchAll().first;
    expect(all.where((x) => x.likedAt != null).map((x) => x.id), [first]);

    // Liking again keeps the date of the existing like.
    final likedAt = all.firstWhere((x) => x.id == first).likedAt;
    await tracks.setLiked([first], liked: true);
    all = await tracks.watchAll().first;
    expect(all.firstWhere((x) => x.id == first).likedAt, likedAt);

    await tracks.setLiked([first], liked: false);
    all = await tracks.watchAll().first;
    expect(all.every((x) => x.likedAt == null), isTrue);
  });

  testWidgets('a real playback writes a play row', (t) async {
    final wav = File('${tmp.path}/tone.wav')..writeAsBytesSync(_tone(5));
    await import([wav.path]);
    final imported = await tracks.watchAll().first;
    expect(imported, hasLength(1));

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        storageProvider.overrideWithValue(storage),
        audioEngineProvider.overrideWith((ref) {
          final engine = JustAudioEngine();
          ref.onDispose(engine.dispose);
          return engine;
        }),
      ],
    );
    addTearDown(container.dispose);
    // The player follows the tracks stream, so keep it alive and loaded.
    container
      ..listen(tracksProvider, (_, _) {})
      ..listen(playerPositionProvider, (_, _) {});
    final player = container.read(playerProvider.notifier);

    await t.runAsync(() async {
      await container.read(tracksProvider.future);
      await player.playList(
        imported,
        start: 0,
        source: const QueueSource.songs(),
      );
      final end = DateTime.now().add(const Duration(seconds: 15));
      while (container.read(playerPositionProvider).value == null ||
          container.read(playerPositionProvider).value! <
              const Duration(milliseconds: 2500)) {
        if (DateTime.now().isAfter(end)) fail('playback never reached 2.5 s');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await player.togglePlay(); // pause: a save point
      // History writes are not awaited by playback; give them a moment.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });

    final rows = await db.select(db.plays).get();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.trackId, imported.single.id);
    expect(row.listenedMs, greaterThanOrEqualTo(1000));
    expect(row.listenedMs, lessThan(5500));
    // Paused after 2.5 s of a 5 s song: heard, but not a play yet.
    expect(row.counted, isFalse);
    expect(row.sourceKind, QueueSourceKind.songs.name);
    expect(row.sourceKey, isNull);
    final after = (await tracks.watchAll().first).single;
    expect(after.playCount, 0);
    expect(after.lastPlayedAt, isNull);
  });
}
