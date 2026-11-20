import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/edit/track_tags.dart';

enum DownloadPhase {
  waiting,
  downloading,

  /// Tags written, the Importer adds it; can no longer be cancelled.
  importing,
  done,

  /// The same file was already in the library.
  duplicate,
  failed,
  cancelled,
}

/// One song in the download queue.
class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.result,
    required this.tags,
    this.phase = DownloadPhase.waiting,
    this.received = 0,
    this.total = 0,
    this.error,
  });

  final int id;
  final OnlineResult result;

  /// Title, artist and album as confirmed in the download sheet.
  final TrackTags tags;
  final DownloadPhase phase;

  /// Bytes received and expected while downloading.
  final int received;
  final int total;

  /// Why it failed, or "Already in your library" for a duplicate.
  final String? error;

  bool get isActive =>
      phase == DownloadPhase.waiting ||
      phase == DownloadPhase.downloading ||
      phase == DownloadPhase.importing;

  DownloadJob copyWith({
    DownloadPhase? phase,
    int? received,
    int? total,
    String? Function()? error,
  }) => DownloadJob(
    id: id,
    result: result,
    tags: tags,
    phase: phase ?? this.phase,
    received: received ?? this.received,
    total: total ?? this.total,
    error: error == null ? this.error : error(),
  );
}
