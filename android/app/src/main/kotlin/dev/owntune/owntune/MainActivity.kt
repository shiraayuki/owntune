package dev.owntune.owntune

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service needs its activity so the playback service can share the
// Flutter engine.
class MainActivity : AudioServiceActivity()
