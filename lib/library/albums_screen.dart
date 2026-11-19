import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/songs_screen.dart';

/// The Albums tab: a two-column grid (`.grid`), or the empty states.
class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider).value;
    if (library == null) return const SizedBox.shrink();
    if (library.isEmpty) return const EmptyLibrary();
    if (library.albums.isEmpty) return const _NoAlbums();

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final width = (constraints.maxWidth - 32 - gap) / 2;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            MediaQuery.paddingOf(context).bottom + 16,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: gap,
            mainAxisSpacing: 20,
            mainAxisExtent: AlbumCard.heightFor(
              width,
              MediaQuery.textScalerOf(context),
            ),
          ),
          itemCount: library.albums.length,
          itemBuilder: (context, i) {
            final album = library.albums[i];
            return AlbumCard(
              album: album,
              subtitle: album.artist,
              onTap: () => openAlbum(context, album.key, backLabel: 'Albums'),
            );
          },
        );
      },
    );
  }
}

/// Square cover with title and a subtitle below (`.album`).
class AlbumCard extends ConsumerWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.subtitle,
    this.width,
    this.onTap,
  });

  final Album album;
  final String subtitle;

  /// Fixed width (e.g. in a horizontal row); fills the parent when null.
  final double? width;
  final VoidCallback? onTap;

  /// Line height as a multiple of the 15pt font size.
  static const _lineHeight = 20 / 15;

  /// Height of a card [width] wide at [scaler]: cover, 7pt gap and two text
  /// lines.
  static double heightFor(double width, TextScaler scaler) =>
      width + 7 + 2 * (scaler.scale(15) * _lineHeight).ceilToDouble();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final storage = ref.watch(storageProvider);
    final cover = album.coverFile;
    Widget card(double side) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Artwork(
          file: cover == null ? null : storage.coverFile(cover),
          size: side,
          radius: 10,
        ),
        const SizedBox(height: 7),
        Text(
          album.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            height: _lineHeight,
            fontWeight: FontWeight.w600,
            color: c.text,
          ),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, height: _lineHeight, color: c.muted),
        ),
      ],
    );
    final width = this.width;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: width != null
          ? SizedBox(width: width, child: card(width))
          : LayoutBuilder(
              builder: (context, constraints) => card(constraints.maxWidth),
            ),
    );
  }
}

class _NoAlbums extends StatelessWidget {
  const _NoAlbums();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Text(
            'No albums – songs without an album tag appear under Songs and '
            'Artists.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: c.muted),
          ),
        ),
      ),
    );
  }
}
