import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/update/update_controller.dart';
import 'package:owntune/update/update_launcher.dart';

/// "owntune 0.11.0 is available · Update · ✕" at the top of Home while a
/// newer release is offered and not dismissed.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateControllerProvider);
    final version = info.available;
    if (!info.showBanner || version == null) return const SizedBox.shrink();
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      key: const Key('update-banner'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: c.fill,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Icon(CupertinoIcons.arrow_down_circle, size: 22, color: c.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'owntune $version is available',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(updateLauncherProvider).open(),
              style: TextButton.styleFrom(foregroundColor: c.accent),
              child: const Text(
                'Update',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: () =>
                  ref.read(updateControllerProvider.notifier).dismiss(),
              icon: Icon(CupertinoIcons.xmark, size: 16, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
