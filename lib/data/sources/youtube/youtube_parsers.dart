import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/youtube/innertube_clients.dart';
import 'package:owntune/edit/track_tags.dart';

/// Parsers for innertube responses. They walk the JSON loosely (by renderer
/// name, wherever it sits), because YouTube moves containers around more
/// often than it changes the renderers themselves.

final _changed = changedError('YouTube');

/// Songs from a YouTube Music search response (`WEB_REMIX`, songs filter).
List<OnlineResult> parseMusicSearch(Map<String, Object?> json) {
  if (json['contents'] == null) throw _changed;
  return [
    for (final row in _findAll(json, 'musicResponsiveListItemRenderer'))
      ?_musicRow(row),
  ];
}

/// Videos from a YouTube search response (`WEB`, videos filter).
List<OnlineResult> parseVideoSearch(Map<String, Object?> json) {
  if (json['contents'] == null) throw _changed;
  return [for (final row in _findAll(json, 'videoRenderer')) ?_videoRow(row)];
}

/// The M4A audio stream from a player response.
RangedStream parsePlayer(Map<String, Object?> json) {
  final status = _map(json['playabilityStatus']);
  if (status?['status'] != 'OK') {
    final reason = status?['reason'] ?? status?['status'] ?? 'no answer';
    throw OnlineError('YouTube: $reason');
  }
  final formats = _list(_map(json['streamingData'])?['adaptiveFormats']);
  final format = formats
      .map(_map)
      .where((f) => f?['itag'] == m4aAudioItag && f?['url'] is String)
      .firstOrNull;
  if (format == null) throw const OnlineError('No M4A audio for this video');
  return RangedStream(
    url: Uri.parse(format['url']! as String),
    contentLength: int.tryParse('${format['contentLength']}') ?? 0,
    extension: 'm4a',
    bitrate: (format['bitrate'] as num?)?.toInt() ?? 0,
  );
}

OnlineResult? _musicRow(Map<String, Object?> row) {
  final videoId = _map(row['playlistItemData'])?['videoId'];
  if (videoId is! String) return null;
  final columns = _list(row['flexColumns'])
      .map(
        (c) => _list(
          _map(
            _map(
              _map(c)?['musicResponsiveListItemFlexColumnRenderer'],
            )?['text'],
          )?['runs'],
        ).map(_map).whereType<Map<String, Object?>>().toList(),
      )
      .toList();
  if (columns.isEmpty) return null;
  final title = columns[0].map((r) => r['text'] ?? '').join().trim();
  final details = columns.length > 1 ? columns[1] : <Map<String, Object?>>[];

  final artists = [
    for (final r in details)
      if (_pageType(r) == 'MUSIC_PAGE_TYPE_ARTIST') '${r['text']}'.trim(),
  ];
  if (artists.isEmpty && details.isNotEmpty) {
    // Artists without a channel page come as plain text before the first
    // " • " separator.
    final plain = details
        .map((r) => '${r['text']}')
        .takeWhile((t) => t.trim() != '•')
        .join()
        .trim();
    if (plain.isNotEmpty) artists.add(plain);
  }
  final album = details
      .where((r) => _pageType(r) == 'MUSIC_PAGE_TYPE_ALBUM')
      .map((r) => '${r['text']}'.trim())
      .firstOrNull;
  final duration = details
      .map((r) => '${r['text']}'.trim())
      .where(_durationPattern.hasMatch)
      .lastOrNull;

  final thumbnails = _thumbnails(
    _map(_map(row['thumbnail'])?['musicThumbnailRenderer'])?['thumbnail'],
  );
  if (thumbnails.isEmpty) return null;
  final thumbnail = thumbnails.last.url;
  final artist = artists.isEmpty ? null : artists.join(', ');
  return OnlineResult(
    sourceKey: 'youtube:$videoId',
    id: videoId,
    source: OnlineSourceId.ytmusic,
    title: title,
    subtitle: [?artist, ?album].join(' · '),
    duration: duration == null ? null : _parseDuration(duration),
    thumbnail: thumbnail,
    coverUrl: Uri.parse(
      thumbnail.toString().replaceFirst(_sizeSuffix, '=w1200-h1200'),
    ),
    squareCover: true,
    channel: null,
    tags: TrackTags(title: title, artist: artist, album: album),
  );
}

OnlineResult? _videoRow(Map<String, Object?> row) {
  final videoId = row['videoId'];
  if (videoId is! String) return null;
  final thumbnails = _thumbnails(row['thumbnail']);
  if (thumbnails.isEmpty) return null;
  final bySize = [...thumbnails]..sort((a, b) => a.width.compareTo(b.width));
  final channel = _text(row['ownerText']);
  final views = _text(row['shortViewCountText']);
  final length = _text(row['lengthText']);
  return OnlineResult(
    sourceKey: 'youtube:$videoId',
    id: videoId,
    source: OnlineSourceId.youtube,
    title: _text(row['title']),
    subtitle: [channel, views].where((s) => s.isNotEmpty).join(' · '),
    duration: _durationPattern.hasMatch(length) ? _parseDuration(length) : null,
    thumbnail: bySize
        .firstWhere((t) => t.width >= 320, orElse: () => bySize.last)
        .url,
    coverUrl: bySize.last.url,
    squareCover: false,
    channel: channel.isEmpty ? null : channel,
    tags: const TrackTags(),
  );
}

final _durationPattern = RegExp(r'^\d+:\d{2}(:\d{2})?$');
final _sizeSuffix = RegExp(r'=w\d+-h\d+[^/]*$');

Duration _parseDuration(String text) {
  var seconds = 0;
  for (final part in text.split(':')) {
    seconds = seconds * 60 + int.parse(part);
  }
  return Duration(seconds: seconds);
}

typedef _Thumb = ({Uri url, int width});

List<_Thumb> _thumbnails(Object? container) => [
  for (final t in _list(_map(container)?['thumbnails']).map(_map))
    if (t?['url'] case final String url)
      (url: Uri.parse(url), width: (t?['width'] as num?)?.toInt() ?? 0),
];

String? _pageType(Map<String, Object?> run) {
  final browse = _map(_map(run['navigationEndpoint'])?['browseEndpoint']);
  final configs = _map(browse?['browseEndpointContextSupportedConfigs']);
  return _map(configs?['browseEndpointContextMusicConfig'])?['pageType']
      as String?;
}

/// `simpleText` or the joined `runs` of a text object.
String _text(Object? t) {
  final m = _map(t);
  if (m == null) return '';
  if (m['simpleText'] case final String s) return s.trim();
  return _list(m['runs']).map((r) => _map(r)?['text'] ?? '').join().trim();
}

Map<String, Object?>? _map(Object? v) =>
    v is Map ? v.cast<String, Object?>() : null;

List<Object?> _list(Object? v) => v is List ? v : const [];

Iterable<Map<String, Object?>> _findAll(Object? node, String key) sync* {
  if (node is Map) {
    if (node[key] case final Map found) yield found.cast<String, Object?>();
    for (final v in node.values) {
      yield* _findAll(v, key);
    }
  } else if (node is List) {
    for (final v in node) {
      yield* _findAll(v, key);
    }
  }
}
