import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/youtube/innertube_client.dart';
import 'package:owntune/data/sources/youtube/youtube_parsers.dart';

/// The two YouTube sources, sharing one [InnertubeClient] (and so one
/// visitorData).
class YoutubeSources {
  YoutubeSources(HttpTransport http) : this._(InnertubeClient(http));

  YoutubeSources._(InnertubeClient client)
    : music = YoutubeMusicSource(client),
      video = YoutubeSource(client);

  final YoutubeMusicSource music;
  final YoutubeSource video;
}

/// Songs from YouTube Music, with title, artist, album and album art.
class YoutubeMusicSource implements OnlineSource {
  YoutubeMusicSource(this._client);

  final InnertubeClient _client;

  @override
  OnlineSourceId get id => OnlineSourceId.ytmusic;

  @override
  Future<List<OnlineResult>> search(String query) async =>
      parseMusicSearch(await _client.musicSearch(query));

  @override
  Future<ResolvedStream> resolve(OnlineResult result) async =>
      parsePlayer(await _client.player(result.videoId));
}

/// Any video from YouTube.
class YoutubeSource implements OnlineSource {
  YoutubeSource(this._client);

  final InnertubeClient _client;

  @override
  OnlineSourceId get id => OnlineSourceId.youtube;

  @override
  Future<List<OnlineResult>> search(String query) async =>
      parseVideoSearch(await _client.videoSearch(query));

  @override
  Future<ResolvedStream> resolve(OnlineResult result) async =>
      parsePlayer(await _client.player(result.videoId));
}
