import 'package:owntune/edit/track_tags.dart';

/// The searchable online sources; [name] is the value stored in the settings.
enum OnlineSourceId { ytmusic, youtube }

/// One search result that can be downloaded.
class OnlineResult {
  const OnlineResult({
    required this.sourceKey,
    required this.videoId,
    required this.source,
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.thumbnail,
    required this.coverUrl,
    required this.squareCover,
    required this.channel,
    required this.tags,
  });

  /// Stable id stored on the track, e.g. `youtube:<videoId>`. Songs and
  /// videos share it, so "In Library" works across both.
  final String sourceKey;
  final String videoId;
  final OnlineSourceId source;

  /// Song title (YouTube Music) or the raw video title (YouTube).
  final String title;

  /// "Artist · Album" for songs, "Channel · 2.8B views" for videos.
  final String subtitle;
  final Duration? duration;

  /// Small image for the result row.
  final Uri thumbnail;

  /// Large image for the file's cover.
  final Uri? coverUrl;

  /// True when [coverUrl] is square album art; false for 16:9 video frames,
  /// which are cropped to a square.
  final bool squareCover;

  /// The uploading channel (videos only).
  final String? channel;

  /// Title, artist and album as the source knows them; empty for videos.
  final TrackTags tags;
}

/// A direct audio stream for one result.
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    required this.contentLength,
    required this.extension,
    required this.bitrate,
  });

  final Uri url;
  final int contentLength;

  /// File extension of the stream, e.g. `m4a`.
  final String extension;
  final int bitrate;
}

/// A failure with a message that is shown to the user as is.
class OnlineError implements Exception {
  const OnlineError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A place to search for music and to resolve results to audio streams.
abstract interface class OnlineSource {
  OnlineSourceId get id;

  Future<List<OnlineResult>> search(String query);

  Future<ResolvedStream> resolve(OnlineResult result);
}
