import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

/// One-time audio setup, run by `startUp()`.
///
/// Linux plays through media_kit (libmpv). On iOS and Android the session
/// is configured for music, so the ring/silent switch does not mute
/// playback. This is not background playback: without `UIBackgroundModes`
/// the app still stops when it leaves the foreground.
Future<void> initAudio() async {
  if (Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized(linux: true);
  }
  if (Platform.isIOS || Platform.isAndroid) {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }
}
