import 'package:owntune/data/sources/hls.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_api.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_client.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_parsers.dart';

/// Tracks from SoundCloud: AAC over HLS.
class SoundcloudSource implements OnlineSource {
  SoundcloudSource(this._client);

  final SoundcloudClient _client;

  @override
  OnlineSourceId get id => OnlineSourceId.soundcloud;

  @override
  Future<List<OnlineResult>> search(String query) async =>
      parseSoundcloudSearch(await _client.search(query));

  /// Fetches the track again (a job that waited in the queue gets fresh
  /// transcodings and a fresh `track_authorization`), picks the
  /// transcoding and reads its media playlist.
  @override
  Future<ResolvedStream> resolve(OnlineResult result) async {
    final track = await _client.track(result.id);
    final availability = availabilityOf(track);
    if (availability != OnlineAvailability.available) {
      throw OnlineError("${availability.note}: this track can't be downloaded");
    }
    final transcoding = pickTranscoding(track);
    final authorization = track['track_authorization'];
    if (transcoding == null || authorization is! String) {
      throw changedError(soundcloudService);
    }
    final playlistUrl = await _client.streamUrl(transcoding.url, authorization);
    final playlist = parseMediaPlaylist(
      await _client.text(playlistUrl),
      playlistUrl,
      service: soundcloudService,
    );
    return SegmentedStream(
      initUrl: playlist.init,
      segments: playlist.segments,
      bitrate: transcoding.kbps * 1000,
    );
  }
}
