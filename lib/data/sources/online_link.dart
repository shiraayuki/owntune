/// Recognizes YouTube and SoundCloud links pasted into Search Online.
library;

const playlistLinkMessage =
    "Playlists can't be downloaded yet. Paste the link of a single song.";
const notASongLinkMessage = "This link isn't a song on YouTube or SoundCloud";

sealed class OnlineLink {
  const OnlineLink();
}

/// A link to one YouTube video (watch, youtu.be, shorts, live, embed).
final class YoutubeLink extends OnlineLink {
  const YoutubeLink(this.videoId);

  final String videoId;
}

/// A link to one SoundCloud track, without query or fragment, with scheme
/// `https`. Hosts like `m.` and `on.` are kept as given.
final class SoundcloudLink extends OnlineLink {
  const SoundcloudLink(this.url);

  final Uri url;
}

/// A link to one of the two sites that is not a single song.
final class UnsupportedLink extends OnlineLink {
  const UnsupportedLink(this.message);

  final String message;
}

const _youtubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
};
const _soundcloudHosts = {
  'soundcloud.com',
  'www.soundcloud.com',
  'm.soundcloud.com',
  'on.soundcloud.com',
};

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _whitespace = RegExp(r'\s');
final _scheme = RegExp(r'^https?://', caseSensitive: false);

/// Returns null when [text] is not a link and should be searched as text.
OnlineLink? parseOnlineLink(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || _whitespace.hasMatch(trimmed)) return null;

  final String candidate;
  if (_scheme.hasMatch(trimmed)) {
    candidate = trimmed;
  } else if (_startsWithKnownHost(trimmed)) {
    candidate = 'https://$trimmed';
  } else {
    return null;
  }

  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty) return null;

  final host = uri.host.toLowerCase();
  try {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (_youtubeHosts.contains(host)) return _youtube(host, segments, uri);
    if (_soundcloudHosts.contains(host)) return _soundcloud(host, segments);
  } on FormatException {
    // Malformed percent-encoding: `Uri.tryParse` accepts it, reading the
    // path or the query throws.
  }
  return const UnsupportedLink(notASongLinkMessage);
}

bool _startsWithKnownHost(String text) {
  final lower = text.toLowerCase();
  for (final host in [..._youtubeHosts, ..._soundcloudHosts]) {
    if (!lower.startsWith(host)) continue;
    if (lower.length == host.length) return true;
    final next = lower[host.length];
    if (next == '/' || next == '?' || next == '#') return true;
  }
  return false;
}

OnlineLink _youtube(String host, List<String> segments, Uri uri) {
  String? id;
  if (host == 'youtu.be') {
    if (segments.isNotEmpty) id = segments.first;
  } else if (segments.length == 1 && segments.first == 'watch') {
    id = uri.queryParameters['v'];
  } else if (segments.length == 2 &&
      const {'shorts', 'live', 'embed'}.contains(segments.first)) {
    id = segments[1];
  } else if (segments.length == 1 &&
      segments.first == 'playlist' &&
      uri.queryParameters.containsKey('list')) {
    return const UnsupportedLink(playlistLinkMessage);
  }
  if (id != null && _videoId.hasMatch(id)) return YoutubeLink(id);
  // `watch?list=…` without a video is a playlist.
  if (segments.length == 1 &&
      segments.first == 'watch' &&
      id == null &&
      uri.queryParameters.containsKey('list')) {
    return const UnsupportedLink(playlistLinkMessage);
  }
  return const UnsupportedLink(notASongLinkMessage);
}

OnlineLink _soundcloud(String host, List<String> segments) {
  final Uri clean = Uri(
    scheme: 'https',
    host: host,
    path: '/${segments.join('/')}',
  );
  if (host == 'on.soundcloud.com') {
    return segments.length == 1
        ? SoundcloudLink(clean)
        : const UnsupportedLink(notASongLinkMessage);
  }
  if (segments.length >= 2 && segments[1] == 'sets') {
    return const UnsupportedLink(playlistLinkMessage);
  }
  // user/track, or user/track/s-token for a private track.
  final isTrack =
      segments.length == 2 ||
      (segments.length == 3 && segments[2].startsWith('s-'));
  if (isTrack && !const {'discover', 'you'}.contains(segments.first)) {
    return SoundcloudLink(clean);
  }
  return const UnsupportedLink(notASongLinkMessage);
}
