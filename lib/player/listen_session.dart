import 'package:owntune/player/queue_source.dart';

/// A play counts once this much of it has been heard.
const countAfter = Duration(seconds: 30);

/// A position step larger than this is a seek or a hiccup, not listening.
const maxStep = Duration(seconds: 3);

/// What was heard of one play-queue entry: the forward steps of the playback
/// position, added up. Each round or entry gets its own session.
class ListenSession {
  ListenSession({
    required this.trackId,
    required this.durationMs,
    required this.sourceKind,
    this.sourceKey,
  });

  final int trackId;
  final int durationMs;
  final QueueSourceKind sourceKind;
  final String? sourceKey;

  /// The row written for this session, set by the controller once inserted.
  int? rowId;

  DateTime? _startedAt;
  int _listenedMs = 0;
  bool _counted = false;
  Duration? _baseline;

  /// When the first step that added time happened.
  DateTime? get startedAt => _startedAt;

  int get listenedMs => _listenedMs;

  bool get counted => _counted;

  /// Adds the forward step from the baseline to [position] (0 < step <= 3 s)
  /// and moves the baseline; returns true exactly once: when this call made
  /// the session counted (>= 30 000 ms).
  bool advance(Duration position, DateTime now) {
    final baseline = _baseline;
    _baseline = position;
    if (baseline == null) return false;
    final step = position - baseline;
    if (step <= Duration.zero || step > maxStep) return false;
    _startedAt ??= now;
    _listenedMs += step.inMilliseconds;
    if (!_counted && _listenedMs >= countAfter.inMilliseconds) {
      _counted = true;
      return true;
    }
    return false;
  }

  /// After a load or a seek: the next step is measured from [position].
  void resetBaseline(Duration position) => _baseline = position;

  /// The entry ended by itself; returns true when that made it counted: at
  /// least 1 s was heard, and either the song is shorter than 30 s or all of
  /// it but the last [maxStep] was heard (it was played, not seeked to the
  /// end).
  bool complete() {
    if (_counted || _listenedMs < 1000) return false;
    final heardToTheEnd = _listenedMs >= durationMs - maxStep.inMilliseconds;
    if (durationMs >= countAfter.inMilliseconds && !heardToTheEnd) return false;
    _counted = true;
    return true;
  }
}
