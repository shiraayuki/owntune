import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/library_storage.dart';
import 'package:owntune/data/loudness_repository.dart';
import 'package:owntune/loudness/loudness_meter.dart';
import 'package:owntune/src/rust/api/loudness.dart' show LoudnessResult;

/// Bump when a better decoder can measure files that failed before: rows
/// that failed with an older version are measured again.
const kLoudnessMeasurerVersion = 1;

/// Measures every track that has no loudness yet, newest first, one at a
/// time, and only while the app is in the foreground: iOS may kill an app
/// that keeps the CPU busy in the background, which would stop the music.
///
/// Never throws: a file that cannot be measured is recorded as failed, and
/// a database error ends the round quietly until the next [kick].
class LoudnessMeasurer {
  LoudnessMeasurer({
    required this._repo,
    required this._storage,
    required this._meter,
    this._foreground = true,
  });

  final LoudnessRepository _repo;
  final LibraryStorage _storage;
  final LoudnessMeter _meter;

  bool _foreground;
  bool _disposed = false;

  /// Set by a [kick] during a round: look for new tracks before stopping.
  bool _again = false;
  int? _job;
  Future<void>? _round;

  /// Completes when no round runs.
  Future<void> get idle => _round ?? Future.value();

  /// Starts a round, or makes the running one look again before it ends.
  void kick() {
    if (_disposed || !_foreground) return;
    if (_round != null) {
      _again = true;
      return;
    }
    _round = _run().whenComplete(() {
      _round = null;
      if (_again) kick();
    });
  }

  /// In the background the running measurement is cancelled and nothing new
  /// starts; back in the foreground the round starts again.
  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      kick();
    } else {
      _cancelRunning();
    }
  }

  void dispose() {
    _disposed = true;
    _cancelRunning();
  }

  bool get _active => !_disposed && _foreground;

  void _cancelRunning() {
    final job = _job;
    if (job != null) _meter.cancel(job);
  }

  Future<void> _run() async {
    try {
      while (_active) {
        _again = false;
        final track = await _repo.nextUnmeasured(kLoudnessMeasurerVersion);
        if (track == null) {
          if (_again) continue;
          break;
        }
        if (!_active) break;

        final job = _meter.newJob();
        _job = job;
        LoudnessResult? result;
        try {
          result = await _meter.measure(
            _storage.audioFile(track.fileName).path,
            job,
          );
        } on Object {
          result = null;
        } finally {
          _job = null;
        }
        if (_disposed) return;
        // Cancelled by going to the background: nothing is stored, and the
        // song is measured from the start next time.
        if (result != null && result.cancelled) continue;

        final lufs = result?.lufs;
        if (lufs != null && lufs.isFinite) {
          await _repo.saveMeasured(track.id, lufs);
        } else {
          await _repo.saveFailed(track.id, kLoudnessMeasurerVersion);
        }
      }
    } on Object {
      // A database error: stop quietly; the next kick tries again.
      _again = false;
    }
  }
}

bool _isForeground(AppLifecycleState? state) => switch (state) {
  null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
  _ => false,
};

/// The app's measurer. It looks for unmeasured tracks whenever the library
/// changes and follows the app lifecycle; watched by `OwntuneApp`.
final loudnessMeasurerProvider = Provider<LoudnessMeasurer>((ref) {
  final measurer = LoudnessMeasurer(
    repo: ref.watch(loudnessRepositoryProvider),
    storage: ref.watch(storageProvider),
    meter: ref.watch(loudnessMeterProvider),
    foreground: _isForeground(WidgetsBinding.instance.lifecycleState),
  );
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) => measurer.setForeground(_isForeground(state)),
  );
  ref.listen(tracksProvider, (_, _) => measurer.kick(), fireImmediately: true);
  ref.onDispose(() {
    lifecycle.dispose();
    measurer.dispose();
  });
  return measurer;
});
