import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/src/rust/api/loudness.dart';

/// Measures the loudness of audio files; the Rust core in the app, a fake in
/// tests.
abstract interface class LoudnessMeter {
  /// A fresh job id for [measure].
  int newJob();

  /// Decodes [path] and measures its integrated loudness. Never throws for a
  /// bad file; the result says what went wrong.
  Future<LoudnessResult> measure(String path, int job);

  /// Makes a running [measure] of [job] return `cancelled` soon.
  void cancel(int job);
}

class RustLoudnessMeter implements LoudnessMeter {
  @override
  int newJob() => newLoudnessJob();

  @override
  Future<LoudnessResult> measure(String path, int job) =>
      measureLoudness(path: path, job: job);

  @override
  void cancel(int job) => cancelLoudness(job: job);
}

final loudnessMeterProvider = Provider<LoudnessMeter>(
  (ref) => RustLoudnessMeter(),
);
