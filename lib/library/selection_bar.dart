import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/edit/edit_info_screen.dart';
import 'package:owntune/library/songs_screen.dart';
import 'package:owntune/playlists/add_to_playlist_sheet.dart';

/// The bar at the bottom of the shell while songs are selected (`.selbar`);
/// replaces the mini player and the tab bar. Edit Info and Delete act on
/// every selected song, also those the search currently hides; so does Add to
/// Playlist (the selection stays when its sheet is cancelled).
class SelectionBar extends ConsumerWidget {
  const SelectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final ids = ref.watch(songSelectionProvider) ?? const <int>{};
    final red = dark ? const Color(0xffff453a) : const Color(0xffff3b30);

    // In library order, so the editor and the delete list read naturally.
    List<Track> selected() => [
      for (final t in ref.read(tracksProvider).value ?? const <Track>[])
        if (ids.contains(t.id)) t,
    ];

    Future<void> editInfo() async {
      final tracks = selected();
      if (tracks.isEmpty) return;
      final saved = await openEditInfo(context, tracks);
      if (saved) ref.read(songSelectionProvider.notifier).end();
    }

    Future<void> addToPlaylist() async {
      final tracks = selected();
      if (tracks.isEmpty) return;
      final added = await showAddToPlaylist(context, tracks);
      if (added) ref.read(songSelectionProvider.notifier).end();
    }

    Future<void> delete() async {
      final tracks = selected();
      if (tracks.isEmpty) return;
      final navigator = Navigator.of(context);
      final confirmed = await confirmDeleteSongs(
        navigator.context,
        ref.read(trackRepositoryProvider),
        tracks,
      );
      if (confirmed) ref.read(songSelectionProvider.notifier).end();
    }

    final any = ids.isNotEmpty;
    return ClipRect(
      key: const Key('selection-bar'),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(minHeight: 49 + bottom),
          padding: EdgeInsets.fromLTRB(8, 8, 8, bottom),
          decoration: BoxDecoration(
            color: dark
                ? const Color.fromRGBO(22, 22, 28, 0.82)
                : const Color.fromRGBO(251, 250, 247, 0.86),
            border: Border(top: BorderSide(color: c.line, width: 0.5)),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Action(
                  icon: CupertinoIcons.pencil,
                  label: 'Edit Info',
                  color: c.accent,
                  onTap: any ? editInfo : null,
                ),
                _Action(
                  icon: CupertinoIcons.text_badge_plus,
                  label: 'Add to Playlist',
                  color: c.accent,
                  onTap: any ? addToPlaylist : null,
                ),
                _Action(
                  icon: CupertinoIcons.trash,
                  label: 'Delete',
                  color: red,
                  onTap: any ? delete : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One 96pt column of the bar: 24pt icon over an 11pt label; [faint] when
/// disabled.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final color = onTap == null ? c.faint : (this.color ?? c.accent);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 96,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
