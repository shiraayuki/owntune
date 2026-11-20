import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/download/downloads_sheet.dart';

/// Opens the downloads sheet. Visible while downloads wait or run (badge:
/// how many) and while one has failed (warning badge); after the last one
/// succeeds it shows a check for 3 s and hides.
class DownloadsButton extends ConsumerStatefulWidget {
  const DownloadsButton({super.key, this.round = true});

  /// The 44pt circle of the title row; false for the plain accent icon of a
  /// navigation row.
  final bool round;

  @override
  ConsumerState<DownloadsButton> createState() => _DownloadsButtonState();
}

class _DownloadsButtonState extends ConsumerState<DownloadsButton> {
  var _celebrating = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(downloadControllerProvider, (before, now) {
      final wasActive = before?.any((j) => j.isActive) ?? false;
      final active = now.any((j) => j.isActive);
      final failed = now.any((j) => j.phase == DownloadPhase.failed);
      if (wasActive && !active && !failed) {
        _timer?.cancel();
        setState(() => _celebrating = true);
        _timer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _celebrating = false);
        });
      } else if (active && _celebrating) {
        _timer?.cancel();
        setState(() => _celebrating = false);
      }
    });
    final jobs = ref.watch(downloadControllerProvider);
    final active = jobs.where((j) => j.isActive).length;
    final failed = jobs.any((j) => j.phase == DownloadPhase.failed);
    if (active == 0 && !failed && !_celebrating) return const SizedBox.shrink();

    final c = Theme.of(context).extension<OwntuneColors>()!;
    final icon = active == 0 && !failed
        ? CupertinoIcons.checkmark
        : CupertinoIcons.arrow_down_circle;
    final Widget? badge = failed
        ? const _Badge(
            color: Color(0xffff3b30),
            child: Icon(
              CupertinoIcons.exclamationmark,
              size: 11,
              color: Colors.white,
            ),
          )
        : active > 0
        ? _Badge(
            color: c.accent,
            child: Text(
              '$active',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.accentText,
              ),
            ),
          )
        : null;

    final button = widget.round
        ? RoundIconButton(
            icon: icon,
            tooltip: 'Downloads',
            onPressed: () => showDownloadsSheet(context),
          )
        : IconButton(
            tooltip: 'Downloads',
            onPressed: () => showDownloadsSheet(context),
            icon: Icon(icon, size: 24, color: c.accent),
          );
    final shown = Semantics(
      label: active > 0 ? '$active downloads running' : null,
      child: Stack(
        key: const Key('downloads-button'),
        clipBehavior: Clip.none,
        children: [
          button,
          if (badge != null) Positioned(right: -2, top: -2, child: badge),
        ],
      ),
    );
    // The title row's buttons are 8pt apart; the gap goes with the button.
    return widget.round
        ? Padding(padding: const EdgeInsets.only(right: 8), child: shown)
        : shown;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    ),
  );
}
