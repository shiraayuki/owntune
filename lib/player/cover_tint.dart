import 'dart:isolate';

import 'package:material_ui/material_ui.dart' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/player/cover_colors.dart';

/// The controls on a cover colour, as in Spotify: white, with a near-black
/// icon on the play button.
const tintAccent = Color(0xffffffff);
const tintOnAccent = Color(0xff121212);

/// The Now Playing colours of a cover file (by name), computed once per
/// session from a 64×64 version of the image in a background isolate; null
/// when the file is missing or no image.
final coverColorsProvider = FutureProvider.family<CoverColors?, String>((
  ref,
  name,
) async {
  final file = ref.watch(storageProvider).coverFile(name);
  try {
    final bytes = await file.readAsBytes();
    return await Isolate.run(() => coverColorsFromImage(bytes));
  } on Object {
    return null;
  }
});
