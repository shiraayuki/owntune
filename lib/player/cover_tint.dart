import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/player/cover_colors.dart';

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
