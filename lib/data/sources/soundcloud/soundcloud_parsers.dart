import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_api.dart';
import 'package:owntune/download/guess_tags.dart';
import 'package:owntune/edit/track_tags.dart';

/// Parsers for SoundCloud's API answers. They read only the fields they need
/// and treat every one of them as optional, except for the shape of the
/// search answer.

/// The tracks of a search answer; other kinds (users, sets) are skipped.
List<OnlineResult> parseSoundcloudSearch(Map<String, Object?> json) {
  final collection = json['collection'];
  if (collection is! List) throw changedError(soundcloudService);
  return [
    for (final item in collection)
      if (item is Map<String, Object?> && item['kind'] == 'track')
        parseSoundcloudTrack(item),
  ];
}

/// One result row from a track object (search item or track call).
OnlineResult parseSoundcloudTrack(Map<String, Object?> track) {
  final id = '${track['id']}';
  final user = _map(track['user']);
  final username = _text(user?['username']) ?? '';
  final plays = track['playback_count'];
  final availability = availabilityOf(track);
  // `duration` is the length of the file the transcodings give (30 s for a
  // preview); `full_duration` can differ by a few ms.
  final milliseconds = _int(track['duration']) ?? _int(track['full_duration']);
  return OnlineResult(
    sourceKey: 'soundcloud:$id',
    id: id,
    source: OnlineSourceId.soundcloud,
    title: _text(track['title']) ?? '',
    subtitle: [
      if (username.isNotEmpty) username,
      if (plays is int) '${compactCount(plays)} plays',
    ].join(' · '),
    duration: milliseconds == null
        ? null
        : Duration(milliseconds: milliseconds),
    thumbnail: soundcloudArtwork(track, rowArtworkSize) ?? Uri(),
    coverUrl: soundcloudArtwork(track, coverArtworkSize),
    squareCover: true,
    channel: null,
    tags: soundcloudTags(track),
    availability: availability,
    kbps: availability == OnlineAvailability.available
        ? pickTranscoding(track)?.kbps
        : null,
  );
}

/// The transcoding to download: unencrypted HLS of AAC in MP4, not snipped,
/// 160 kbps before 96 kbps; null when there is none.
({Uri url, int kbps})? pickTranscoding(Map<String, Object?> track) {
  final usable = _transcodings(track).where(_isUsableFormat).toList();
  for (final (:preset, :kbps) in aacPresets) {
    for (final t in usable) {
      final url = _text(t['url']);
      if (t['preset'] == preset && t['snipped'] != true && url != null) {
        return (url: Uri.parse(url), kbps: kbps);
      }
    }
  }
  return null;
}

/// Whether the track can be downloaded, as far as the API tells.
OnlineAvailability availabilityOf(Map<String, Object?> track) {
  final policy = track['policy'];
  if (policy == blockedPolicy) return OnlineAvailability.unavailable;
  if (policy == previewPolicy) return OnlineAvailability.previewOnly;
  if (pickTranscoding(track) != null) return OnlineAvailability.available;

  final transcodings = _transcodings(track);
  final snipped = transcodings.any(
    (t) => _isUsableFormat(t) && _isAacPreset(t) && t['snipped'] == true,
  );
  if (snipped) return OnlineAvailability.previewOnly;
  final encrypted = transcodings.any(
    (t) => '${_map(t['format'])?['protocol']}'.contains('encrypted'),
  );
  if (encrypted) return OnlineAvailability.protected;
  return OnlineAvailability.unavailable;
}

/// Title, artist, album, genre and year to prefill the download sheet.
///
/// A title with an "Artist - Title" separator is split like a YouTube video
/// title. Otherwise the title stays as it is (minus noise brackets) and the
/// artist is the publisher's artist, else the uploader.
TrackTags soundcloudTags(Map<String, Object?> track) {
  final raw = _text(track['title']) ?? '';
  final username = _text(_map(track['user'])?['username']) ?? '';
  final publisher = _map(track['publisher_metadata']);

  // Without a channel, only a separator can give an artist.
  final plain = guessTags(videoTitle: raw, channel: '');
  final String? title;
  final String? artist;
  if (plain.artist != null) {
    final split = guessTags(videoTitle: raw, channel: username);
    title = split.title;
    artist = split.artist;
  } else {
    title = plain.title;
    artist = _text(publisher?['artist']) ?? _nonEmpty(username);
  }

  final genre = _text(track['genre']);
  return TrackTags(
    title: _nonEmpty(title) ?? _nonEmpty(raw),
    artist: _nonEmpty(artist),
    album:
        _text(publisher?['album_title']) ?? _text(publisher?['release_title']),
    genre: genre,
    year: _year(track['release_date']),
  );
}

/// The artwork (else the uploader's avatar) in [size], e.g. `t300x300`;
/// null when the track has neither.
Uri? soundcloudArtwork(Map<String, Object?> track, String size) {
  final url =
      _text(track['artwork_url']) ?? _text(_map(track['user'])?['avatar_url']);
  if (url == null) return null;
  return Uri.parse(url.replaceFirst(artworkSizeSuffix, '-$size'));
}

/// A play count as 950, 6.2K, 48K, 2.1M: truncated, one decimal below 10,
/// no trailing ".0".
String compactCount(int n) {
  const units = [(1000000000, 'B'), (1000000, 'M'), (1000, 'K')];
  for (final (size, letter) in units) {
    if (n < size) continue;
    if (n >= size * 10) return '${n ~/ size}$letter';
    final tenths = n * 10 ~/ size;
    return tenths % 10 == 0
        ? '${tenths ~/ 10}$letter'
        : '${tenths ~/ 10}.${tenths % 10}$letter';
  }
  return '$n';
}

List<Map<String, Object?>> _transcodings(Map<String, Object?> track) => [
  for (final t in _list(_map(track['media'])?['transcodings']))
    if (t is Map<String, Object?>) t,
];

bool _isUsableFormat(Map<String, Object?> transcoding) {
  final format = _map(transcoding['format']);
  return format?['protocol'] == hlsProtocol &&
      '${format?['mime_type']}'.startsWith(mp4MimePrefix);
}

bool _isAacPreset(Map<String, Object?> transcoding) =>
    aacPresets.any((p) => p.preset == transcoding['preset']);

int? _year(Object? releaseDate) {
  final text = _text(releaseDate);
  if (text == null || text.length < 4) return null;
  return int.tryParse(text.substring(0, 4));
}

Map<String, Object?>? _map(Object? v) => v is Map<String, Object?> ? v : null;

List<Object?> _list(Object? v) => v is List ? v : const [];

int? _int(Object? v) => v is num ? v.toInt() : null;

/// [v] as trimmed text; null when it is not a string or blank.
String? _text(Object? v) => v is String ? _nonEmpty(v.trim()) : null;

String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;
