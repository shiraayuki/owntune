import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';

/// The Playlists tab. Playlists arrive in M4; until then an empty state.
class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        44,
        0,
        44,
        MediaQuery.paddingOf(context).bottom + 60,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.music_note_list, size: 64, color: c.faint),
            const SizedBox(height: 20),
            Text(
              'No playlists yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Creating playlists arrives in a later version.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
