import 'dart:math' as math;

/// The level songs are lowered to (Spotify "Normal").
const kTargetLufs = -14.0;

/// The lowest gain, a guard against a broken measurement (−20 dB).
const kMinGain = 0.1;

/// The player volume for a song of integrated loudness [lufs]. Only lowers:
/// iOS cannot raise the volume above 1.0, so quieter songs play unchanged.
/// No measurement, a broken one, or [enabled] false → 1.0.
double normalizationGain(double? lufs, {required bool enabled}) {
  if (!enabled || lufs == null || !lufs.isFinite) return 1.0;
  final gain = math.pow(10, (kTargetLufs - lufs) / 20).toDouble();
  return gain.clamp(kMinGain, 1.0);
}
