import 'package:owntune/data/sources/online_link.dart';
import 'package:owntune/edit/track_tags.dart';

/// The searchable online sources; [name] is the value stored in the settings.
enum OnlineSourceId { ytmusic, youtube, soundcloud }

/// Whether a result can be downloaded, as far as the search can tell.
enum OnlineAvailability {
  available,
  protected,
  previewOnly,
  unavailable;

  /// The short note shown on a result row; null when it can be downloaded.
  String? get note => switch (this) {
    available => null,
    protected => 'Protected',
    previewOnly => 'Preview only',
    unavailable => 'Not available',
  };
}

/// One search result that can be downloaded.
class OnlineResult {
  const OnlineResult({
    required this.sourceKey,
    required this.id,
    required this.source,
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.thumbnail,
    required this.coverUrl,
    required this.squareCover,
    required this.channel,
    required this.tags,
    this.availability = OnlineAvailability.available,
    this.kbps,
  });

  /// Stable id stored on the track, e.g. `youtube:<id>`. Songs and videos
  /// share it, so "In Library" works across both.
  final String sourceKey;

  /// The source's own id (a YouTube video id, a SoundCloud track id).
  final String id;
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

  /// Whether the result can be downloaded.
  final OnlineAvailability availability;

  /// The bitrate of the preset SoundCloud offers; null for YouTube.
  final int? kbps;
}

/// An audio stream for one result: a file fetched in ranges or a list of
/// HLS segments.
sealed class ResolvedStream {
  const ResolvedStream();

  /// File extension of the stream, e.g. `m4a`.
  String get extension;
  int get bitrate;
}

/// One file that a plain range request can fetch in chunks.
final class RangedStream extends ResolvedStream {
  const RangedStream({
    required this.url,
    required this.contentLength,
    required this.extension,
    required this.bitrate,
  });

  final Uri url;
  final int contentLength;

  @override
  final String extension;
  @override
  final int bitrate;
}

/// One media segment of an HLS stream.
class HlsSegment {
  const HlsSegment(this.url, this.duration);

  final Uri url;
  final Duration duration;
}

/// An fMP4 HLS stream: an init segment and the media segments in order.
final class SegmentedStream extends ResolvedStream {
  const SegmentedStream({
    required this.initUrl,
    required this.segments,
    required this.bitrate,
  });

  final Uri initUrl;
  final List<HlsSegment> segments;

  @override
  final int bitrate;

  @override
  String get extension => 'm4a';

  /// The summed duration of all segments.
  Duration get total =>
      segments.fold(Duration.zero, (sum, s) => sum + s.duration);

  /// The file size to expect, from the bitrate and [total].
  int get estimatedBytes => bitrate * total.inMilliseconds ~/ 8000;
}

/// A failure with a message that is shown to the user as is.
class OnlineError implements Exception {
  const OnlineError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A non-200 answer from [service].
class HttpStatusError extends OnlineError {
  HttpStatusError(this.service, this.statusCode)
    : super("$service didn't answer: HTTP $statusCode");

  final String service;
  final int statusCode;
}

/// The error for a response that is not what [service] normally sends.
OnlineError changedError(String service) =>
    OnlineError('$service changed something; owntune needs an update');

/// A place to search for music and to resolve results to audio streams.
abstract interface class OnlineSource {
  OnlineSourceId get id;

  Future<List<OnlineResult>> search(String query);

  Future<ResolvedStream> resolve(OnlineResult result);

  /// The one song that [link] points to. Throws [ArgumentError] for a link
  /// of the other site and [OnlineError] when it is not a downloadable song.
  Future<OnlineResult> lookup(OnlineLink link);
}
