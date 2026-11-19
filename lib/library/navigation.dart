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
  const NavRow({super.key, required this.backLabel});

  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
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
                    Icon(
                      CupertinoIcons.chevron_left,
                      size: 24,
                      color: c.accent,
                    ),
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
          ),
        ),
      ),
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
