import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/download/cover_image.dart';
import 'package:owntune/download/stream_download.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/src/rust/api/library.dart';
import 'package:owntune/src/rust/api/metadata.dart';
import 'package:owntune/src/rust/frb_generated.dart';

import '../test/support/fakes.dart' show MemorySoundcloudClientIdStore;

/// Against the real YouTube and SoundCloud: off by default (CI runner IPs are often
/// bot-flagged, and a red CI must not mean "YouTube changed"). Run locally
/// before each release:
///
///     flutter test integration_test/online_live_test.dart -d linux \
///       --dart-define=OWNTUNE_LIVE=true
const live = bool.fromEnvironment('OWNTUNE_LIVE');

/// A container without the app database: SoundCloud's scraped `client_id`
/// only lives in memory for the test.
ProviderContainer liveContainer() => ProviderContainer(
  overrides: [
    soundcloudClientIdStoreProvider.overrideWithValue(
      MemorySoundcloudClientIdStore(),
    ),
  ],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (live) await RustLib.init();
  });

  testWidgets(
    'searches, downloads and imports a Creative Commons song from YouTube',
    (t) async {
      final tmp = Directory.systemTemp.createTempSync('owntune_live_it');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final container = liveContainer();
      addTearDown(container.dispose);
      final http = container.read(httpTransportProvider);
      final music = container.read(
        onlineSourcesProvider,
      )[OnlineSourceId.ytmusic]!;

      final result = (await music.search(
        'Kevin MacLeod Monkeys Spinning Monkeys',
      )).first;
      final stream = await music.resolve(result);
      final part = File('${tmp.path}/audio.part.${stream.extension}');
      await downloadStream(
        http,
        stream,
        part,
        onProgress: (_, _) {},
        cancel: CancelToken(),
      );
      expect(part.lengthSync(), (stream as RangedStream).contentLength);

      final body = await http.get(result.coverUrl!);
      expect(body.statusCode, 200);
      final bytes = Uint8List.fromList(
        await body.stream.expand((c) => c).toList(),
      );
      final cover = await Isolate.run(
        () => prepareCover(bytes, cropToSquare: !result.squareCover),
      );
      expect(cover, isNotNull);

      final error = await container.read(downloadTagWriterProvider)(
        part.path,
        result.tags,
        cover,
      );
      expect(error, isNull);
      final named = part.renameSync('${tmp.path}/live.m4a');

      final storage = LibraryStorage(Directory('${tmp.path}/library'));
      await storage.ensure();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TrackRepository(db, storage);
      final summary = await Importer(
        repo: repo,
        storage: storage,
        read: (p) => readTrack(path: p),
        supportedExtensions: supportedFormats().toSet(),
      ).importFiles([named.path], sourceKeys: {named.path: result.sourceKey});
      expect(summary.added, 1, reason: '${summary.failures}');

      final row = (await repo.watchAll().first).single;
      expect(row.sourceKey, 'youtube:${result.id}');
      expect(row.title, isNotEmpty);
      expect(row.coverFile, isNotNull);
      expect(row.durationMs, greaterThan(120000));
      // ignore: avoid_print
      print(
        'live: "${row.title}" by ${row.artist} on ${row.album}, '
        '${row.durationMs} ms, ${stream.contentLength} bytes',
      );
    },
    skip: !live,
  );

  testWidgets(
    'searches SoundCloud and fetches the init and first segment of a track',
    (t) async {
      final container = liveContainer();
      addTearDown(container.dispose);
      final http = container.read(httpTransportProvider);
      final soundcloud = container.read(
        onlineSourcesProvider,
      )[OnlineSourceId.soundcloud]!;

      final results = await soundcloud.search('linkin park numb');
      expect(results, isNotEmpty);
      final result = results.firstWhere(
        (r) => r.availability == OnlineAvailability.available,
      );
      final stream = await soundcloud.resolve(result) as SegmentedStream;
      expect(stream.segments, isNotEmpty);

      final fetched = <int>[];
      for (final url in [stream.initUrl, stream.segments.first.url]) {
        final body = await http.get(url);
        expect(body.statusCode, 200);
        final bytes = await body.stream.expand((c) => c).toList();
        expect(bytes, isNotEmpty);
        fetched.add(bytes.length);
      }
      expect(result.sourceKey, 'soundcloud:${result.id}');
      // ignore: avoid_print
      print(
        'live: SoundCloud "${result.title}" (${result.subtitle}), '
        '${stream.segments.length} segments, '
        '${stream.total.inSeconds} s, init ${fetched[0]} bytes, '
        'first segment ${fetched[1]} bytes',
      );
    },
    skip: !live,
  );
}
