import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/playlists/playlist_view.dart';

/// The cover of a playlist: [preview] (an unsaved cover) first, then its own
/// cover file, then a 2x2 mosaic of the covers of its first four albums, then
/// the first cover alone (fewer than four), else the placeholder.
class PlaylistArtwork extends ConsumerWidget {
  const PlaylistArtwork({
    super.key,
    required this.playlist,
    required this.size,
    this.preview,
    this.radius = 8,
  });

  final PlaylistView playlist;
  final double size;
  final Uint8List? preview;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageProvider);
    final preview = this.preview;
    if (preview != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(
          preview,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    final own = playlist.coverFile;
    if (own != null) {
      return Artwork(file: storage.coverFile(own), size: size, radius: radius);
    }
    final covers = playlist.mosaicCovers;
    if (covers.length < 4) {
      return Artwork(
        file: covers.isEmpty ? null : storage.coverFile(covers.first),
        size: size,
        radius: radius,
      );
    }
    final half = size / 2;
    Widget cell(String cover) =>
        Artwork(file: storage.coverFile(cover), size: half, radius: 0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Column(
          children: [
            Row(children: [cell(covers[0]), cell(covers[1])]),
            Row(children: [cell(covers[2]), cell(covers[3])]),
          ],
        ),
      ),
    );
  }
}
