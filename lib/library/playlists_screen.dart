import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/placeholder_state.dart';

/// The Playlists tab. Playlists arrive in M4; until then an empty state.
class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderState(
    icon: CupertinoIcons.music_note_list,
    title: 'No playlists yet',
    message: 'Creating playlists arrives in a later version.',
  );
}
