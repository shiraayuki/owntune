import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/library/songs_screen.dart';

/// The heart in Now Playing and the mini player: likes or unlikes [track].
class LikeButton extends ConsumerWidget {
  const LikeButton({super.key, required this.track, this.iconSize = 26});

  final Track track;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final liked = track.likedAt != null;
    final navigator = Navigator.of(context);
    return IconButton(
      tooltip: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
      icon: Icon(
        liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
        size: iconSize,
        color: liked ? c.accent : c.text,
      ),
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      onPressed: () async {
        // Read on tap, and before the await: the widget may be gone by then.
        final repo = ref.read(trackRepositoryProvider);
        try {
          await repo.setLiked([track.id], liked: !liked);
        } catch (e) {
          if (!navigator.mounted) return;
          await showLikeError(navigator.context, e);
        }
      },
    );
  }
}
