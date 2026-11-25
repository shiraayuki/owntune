import 'package:owntune/data/sources/hls.dart';
import 'package:owntune/data/sources/online_link.dart';
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

  /// The track behind a pasted link, via SoundCloud's resolve call.
  @override
  Future<OnlineResult> lookup(OnlineLink link) async {
    if (link is! SoundcloudLink) {
      throw ArgumentError.value(link, 'link', 'not a SoundCloud link');
    }
    var url = link.url;
    if (url.host == 'on.soundcloud.com') {
      // `/resolve` does not know the short links the apps copy; follow the
      // redirect and resolve its target.
      switch (parseOnlineLink((await _client.finalUrl(url)).toString())) {
        case SoundcloudLink(url: final target)
            when target.host != 'on.soundcloud.com':
          url = target;
        case UnsupportedLink(:final message):
          throw OnlineError(message);
        default:
          throw const OnlineError(notASongLinkMessage);
      }
    }
    final Map<String, Object?> answer;
    try {
      answer = await _client.resolveUrl(url);
    } on HttpStatusError catch (e) {
      if (e.statusCode == 404) throw const OnlineError(notASongLinkMessage);
      rethrow;
    }
    switch (answer['kind']) {
      case 'track':
        _requireDownloadable(answer);
        return parseSoundcloudTrack(answer);
      case 'playlist':
        throw const OnlineError(playlistLinkMessage);
      default:
        throw const OnlineError(notASongLinkMessage);
    }
  }

  /// Throws the message for a track that is a preview, protected or gone.
  void _requireDownloadable(Map<String, Object?> track) {
    final availability = availabilityOf(track);
    if (availability != OnlineAvailability.available) {
      throw OnlineError("${availability.note}: this track can't be downloaded");
    }
  }

  /// Fetches the track again (a job that waited in the queue gets fresh
  /// transcodings and a fresh `track_authorization`), picks the
  /// transcoding and reads its media playlist.
  @override
  Future<ResolvedStream> resolve(OnlineResult result) async {
    final track = await _client.track(result.id);
    _requireDownloadable(track);
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
