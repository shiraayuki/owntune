import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/library/album_screen.dart';
import 'package:owntune/library/artist_screen.dart';
import 'package:owntune/library/library.dart';

/// Opens the album detail above the tab shell.
Future<void> openAlbum(
  BuildContext context,
  AlbumKey key, {
  required String backLabel,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => AlbumScreen(albumKey: key, backLabel: backLabel),
  ),
);

/// Opens the artist detail above the tab shell.
Future<void> openArtist(
  BuildContext context,
  String artistKey, {
  required String backLabel,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ArtistScreen(artistKey: artistKey, backLabel: backLabel),
  ),
);

/// Opens the full song list of an artist ("See All").
Future<void> openArtistSongs(
  BuildContext context,
  String artistKey, {
  required String backLabel,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        ArtistSongsScreen(artistKey: artistKey, backLabel: backLabel),
  ),
);

/// 44pt row with a back button: chevron plus the title of the screen
/// underneath (`.navrow .back`).
class NavRow extends StatelessWidget {
  const NavRow({super.key, required this.backLabel, this.trailing});

  final String backLabel;

  /// Shown at the right end, e.g. a "…" button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 44,
        child: Row(children: [_back(context, c), const Spacer(), ?trailing]),
      ),
    );
  }

  Widget _back(BuildContext context, OwntuneColors c) => Semantics(
    button: true,
    label: 'Back to $backLabel',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.chevron_left, size: 24, color: c.accent),
            const SizedBox(width: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                backLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, color: c.accent),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The "…" button of a detail page's top row: a menu with "Edit Info".
class DetailMoreButton extends StatelessWidget {
  const DetailMoreButton({super.key, required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      key: const Key('detail-more'),
      tooltip: 'More',
      icon: Icon(CupertinoIcons.ellipsis, size: 22, color: c.accent),
      onPressed: () async {
        final box = context.findRenderObject()! as RenderBox;
        final overlay =
            Navigator.of(context).overlay!.context.findRenderObject()!
                as RenderBox;
        final at = box.localToGlobal(
          box.size.bottomRight(Offset.zero),
          ancestor: overlay,
        );
        final picked = await showMenu<String>(
          context: context,
          position: RelativeRect.fromRect(
            at & Size.zero,
            Offset.zero & overlay.size,
          ),
          color: dark
              ? const Color.fromRGBO(37, 37, 42, 0.96)
              : const Color.fromRGBO(250, 250, 250, 0.96),
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          constraints: const BoxConstraints.tightFor(width: 250),
          items: [
            PopupMenuItem(
              key: const Key('menu-edit'),
              value: 'edit',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit Info',
                      style: TextStyle(fontSize: 17, color: c.text),
                    ),
                  ),
                  Icon(CupertinoIcons.pencil, size: 20, color: c.text),
                ],
              ),
            ),
          ],
        );
        if (picked == 'edit') onEdit();
      },
    );
  }
}

/// Shows the album or artist that [resolve] finds in the live library.
/// When it disappears (its last song was deleted), the screen pops itself.
class LiveDetail<T extends Object> extends ConsumerStatefulWidget {
  const LiveDetail({super.key, required this.resolve, required this.builder});

  final T? Function(Library library) resolve;
  final Widget Function(BuildContext context, T value) builder;

  @override
  ConsumerState<LiveDetail<T>> createState() => _LiveDetailState<T>();
}

class _LiveDetailState<T extends Object> extends ConsumerState<LiveDetail<T>> {
  var _popping = false;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider).value;
    if (library == null) return const SizedBox.shrink();
    final value = widget.resolve(library);
    if (value != null) return widget.builder(context, value);

    if (!_popping) {
      _popping = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route == null) return;
        // Remove this screen even if another one is on top of it.
        if (route.isCurrent) {
          Navigator.of(context).pop();
        } else if (route.isActive) {
          Navigator.of(context).removeRoute(route);
        }
      });
    }
    return const SizedBox.shrink();
  }
}
