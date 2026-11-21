import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/text_tabs.dart';
import 'package:owntune/library/albums_screen.dart';
import 'package:owntune/library/artists_screen.dart';
import 'package:owntune/library/songs_screen.dart';

/// The sub-tabs of the Library tab, in display order.
enum LibrarySection { songs, albums, artists }

const _labels = {
  LibrarySection.songs: 'Songs',
  LibrarySection.albums: 'Albums',
  LibrarySection.artists: 'Artists',
};

/// Songs | Albums | Artists under one tab. All three screens stay mounted,
/// so each keeps its query and scroll position. The text tabs are
/// hidden while the library is empty (each screen then shows the empty
/// state with "Import Music").
class LibraryTab extends ConsumerWidget {
  const LibraryTab({super.key, required this.section, required this.onSection});

  final LibrarySection section;
  final ValueChanged<LibrarySection> onSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSongs =
        ref.watch(libraryProvider).value?.tracks.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasSongs)
          TextTabs<LibrarySection>(
            key: const ValueKey('library-segments'),
            segments: _labels,
            value: section,
            onChanged: onSection,
          ),
        Expanded(
          child: IndexedStack(
            index: section.index,
            children: const [SongsScreen(), AlbumsScreen(), ArtistsScreen()],
          ),
        ),
      ],
    );
  }
}
