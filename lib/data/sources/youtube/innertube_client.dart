import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/youtube/innertube_clients.dart';

/// The three innertube calls owntune makes. Remembers the visitorData of the
/// last search, which the player call needs.
class InnertubeClient {
  InnertubeClient(this._http);

  final HttpTransport _http;

  /// From the last search response; sent with every player call.
  String? visitorData;

  Future<Map<String, Object?>> musicSearch(String query) => _search(
    musicSearchUrl,
    musicClientName,
    musicClientVersion,
    musicSongsFilter,
    query,
  );

  Future<Map<String, Object?>> videoSearch(String query) => _search(
    videoSearchUrl,
    webClientName,
    webClientVersion,
    videoFilter,
    query,
  );

  /// The player response for [videoId] as the visionOS client. Makes one
  /// music search first when no visitorData is known yet.
  Future<Map<String, Object?>> player(String videoId) async {
    final visitor = visitorData ?? await _fetchVisitorData();
    return _http.postJson(
      playerUrl,
      {
        'context': {
          'client': {
            'clientName': visionClientName,
            'clientVersion': visionClientVersion,
            'deviceMake': visionDeviceMake,
            'deviceModel': visionDeviceModel,
            'userAgent': visionUserAgent,
            'osName': visionOsName,
            'osVersion': visionOsVersion,
            'hl': innertubeLanguage,
            'gl': innertubeRegion,
            'visitorData': ?visitor,
          },
        },
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      },
      headers: {
        'User-Agent': visionUserAgent,
        'X-YouTube-Client-Name': visionClientId,
        'X-YouTube-Client-Version': visionClientVersion,
        'Origin': playerOrigin,
        'X-Goog-Visitor-Id': ?visitor,
      },
    );
  }

  Future<String?> _fetchVisitorData() async {
    await musicSearch('music');
    return visitorData;
  }

  Future<Map<String, Object?>> _search(
    Uri url,
    String clientName,
    String clientVersion,
    String filter,
    String query,
  ) async {
    final json = await _http.postJson(url, {
      'context': {
        'client': {
          'clientName': clientName,
          'clientVersion': clientVersion,
          'hl': innertubeLanguage,
          'gl': innertubeRegion,
        },
      },
      'query': query,
      'params': filter,
    });
    final context = json['responseContext'];
    if (context is Map && context['visitorData'] is String) {
      visitorData = context['visitorData'] as String;
    }
    return json;
  }
}
