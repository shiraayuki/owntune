import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/sources/hls.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/download/stream_download.dart';
import 'package:owntune/edit/track_tags.dart';
import 'package:owntune/import/importer.dart';
import 'package:owntune/src/rust/api/library.dart';
import 'package:owntune/src/rust/api/metadata.dart';
import 'package:owntune/src/rust/frb_generated.dart';

import '../test/support/fakes.dart' show FakeHttpTransport, serveSegments;
import 'support/fixtures.dart';

/// The download pipeline after the network part, with the real Rust core:
/// a YouTube-like DASH M4A, and a SoundCloud-like HLS stream joined from its
/// segments, get tags and are imported with their source keys.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('a downloaded DASH M4A is tagged and imported', (t) async {
    final tmp = Directory.systemTemp.createTempSync('owntune_download_it');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final part = File('${fixturesDir().path}/dash.m4a')
        .copySync('${tmp.path}/audio.part.m4a');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cover = img.encodeJpg(img.Image(width: 32, height: 32));
    final error = await container.read(downloadTagWriterProvider)(
      part.path,
      const TrackTags(title: 'Numb', artist: 'Linkin Park', album: 'Meteora'),
      (data: cover, mime: 'image/jpeg'),
    );
    expect(error, isNull);
    final named = part.renameSync('${tmp.path}/Linkin Park - Numb.m4a');

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
    ).importFiles([named.path], sourceKeys: {named.path: 'youtube:abc'});
    expect(summary.added, 1, reason: '${summary.failures}');

    final row = (await repo.watchAll().first).single;
    expect(row.title, 'Numb');
    expect(row.artist, 'Linkin Park');
    expect(row.album, 'Meteora');
    expect(row.sourceKey, 'youtube:abc');
    expect(row.originalName, 'Linkin Park - Numb.m4a');
    expect(row.coverFile, isNotNull);
    expect(storage.coverFile(row.coverFile!).existsSync(), isTrue);
    final read = (await readTrack(path: storage.audioFile(row.fileName).path))
        .track!;
    expect(read.durationMs, closeTo(1128, 50));
  });

  testWidgets(
    'a joined SoundCloud-like HLS download gets its duration, tags and imports',
    (t) async {
      final tmp = Directory.systemTemp.createTempSync('owntune_hls_it');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final fixtures = fixturesDir();
      List<int> bytes(String name) =>
          File('${fixtures.path}/$name').readAsBytesSync();

      // The fixture's init segment says 0 in mvhd, as SoundCloud's does, and
      // the segments joined without the patch read as an empty song.
      final init = bytes('hls_init.mp4');
      final mvhd = String.fromCharCodes(init).indexOf('mvhd');
      expect(mvhd, isNonNegative);
      expect(init.sublist(mvhd + 20, mvhd + 24), [0, 0, 0, 0]);
      final raw = File('${tmp.path}/raw.m4a')
        ..writeAsBytesSync([
          ...init,
          for (var i = 0; i < 3; i++) ...bytes('hls_seg$i.m4s'),
        ]);
      expect((await readTrack(path: raw.path)).track!.durationMs, lessThan(50));

      final playlist = parseMediaPlaylist(
        File('${fixtures.path}/hls.m3u8').readAsStringSync(),
        Uri.parse('https://example.invalid/hls/hls.m3u8'),
        service: 'SoundCloud',
      );
      final stream = SegmentedStream(
        initUrl: playlist.init,
        segments: playlist.segments,
        bitrate: 32000,
      );
      expect(stream.segments, hasLength(3));
      final http = FakeHttpTransport(
        onGet: serveSegments({
          '/hls/hls_init.mp4': init,
          for (var i = 0; i < 3; i++)
            '/hls/hls_seg$i.m4s': bytes('hls_seg$i.m4s'),
        }),
      );

      final part = File('${tmp.path}/audio.part.m4a');
      await downloadStream(
        http,
        stream,
        part,
        onProgress: (_, _) {},
        cancel: CancelToken(),
        parallel: 2,
      );
      expect(File('${part.path}.progress').existsSync(), isTrue);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final error = await container.read(downloadTagWriterProvider)(
        part.path,
        const TrackTags(title: 'Numb', artist: 'Linkin Park'),
        null,
      );
      expect(error, isNull);
      final named = part.renameSync('${tmp.path}/Linkin Park - Numb.m4a');

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
      ).importFiles([named.path], sourceKeys: {named.path: 'soundcloud:1'});
      expect(summary.added, 1, reason: '${summary.failures}');

      final row = (await repo.watchAll().first).single;
      expect(row.title, 'Numb');
      expect(row.artist, 'Linkin Park');
      expect(row.sourceKey, 'soundcloud:1');
      // The playlist's #EXTINF values add up to 1128 ms (the 1 s tone plus
      // the AAC encoder delay), the same as dash.m4a above.
      expect(stream.total.inMilliseconds, 1128);
      expect(row.durationMs, closeTo(stream.total.inMilliseconds, 50));
    },
  );
}
