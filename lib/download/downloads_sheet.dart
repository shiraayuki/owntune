import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/download/online_image.dart';

/// Opens the download queue (mockup 10).
Future<void> showDownloadsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DownloadsSheet(),
    );

/// The status line of a job in the downloads sheet.
String downloadStatus(DownloadJob job) => switch (job.phase) {
  DownloadPhase.waiting => 'Waiting',
  DownloadPhase.downloading when job.total > 0 =>
    '${_mb(job.received)} of ${_mb(job.total)} MB',
  DownloadPhase.downloading => 'Downloading…',
  DownloadPhase.importing => 'Adding to library…',
  DownloadPhase.done => 'Added to your library',
  DownloadPhase.duplicate => job.error ?? 'Already in your library',
  DownloadPhase.cancelled => 'Cancelled',
  DownloadPhase.failed => "Couldn't download: ${job.error ?? 'unknown error'}",
};

String _mb(int bytes) => (bytes / (1 << 20)).toStringAsFixed(1);

/// Every queued, running and finished download with progress, cancel and
/// retry; Done clears the finished ones.
class DownloadsSheet extends ConsumerWidget {
  const DownloadsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    // Only the list of ids and the counts: progress ticks rebuild the row of
    // their own job, not the whole sheet.
    final summary = ref.watch(downloadControllerProvider.select(_Summary.of));
    final controller = ref.read(downloadControllerProvider.notifier);
    final finished = summary.finished;
    final anyActive = finished < summary.ids.length;
    final bottom = math.max(MediaQuery.viewPaddingOf(context).bottom, 20.0);

    return Material(
      color: c.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, bottom + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: c.faint,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              'Downloads',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              summary.ids.isEmpty
                  ? 'No downloads'
                  : '$finished of ${summary.ids.length} done'
                        '${anyActive ? ' · keep owntune open until they finish' : ''}',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final id in summary.ids)
                    Consumer(
                      builder: (context, ref, _) {
                        final job = ref.watch(
                          downloadControllerProvider.select(
                            (jobs) => jobs.where((j) => j.id == id).firstOrNull,
                          ),
                        );
                        if (job == null) return const SizedBox.shrink();
                        return _JobRow(
                          job: job,
                          onCancel: () => controller.cancel(id),
                          onRetry: () => controller.retry(id),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PillButton(
              label: 'Done',
              secondary: true,
              expand: true,
              onPressed: () {
                controller.clearFinished();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// What the sheet itself shows: the jobs in order and how many finished.
class _Summary {
  const _Summary(this.ids, this.finished);

  factory _Summary.of(List<DownloadJob> jobs) => _Summary([
    for (final j in jobs) j.id,
  ], jobs.where((j) => !j.isActive).length);

  final List<int> ids;
  final int finished;

  @override
  bool operator ==(Object other) =>
      other is _Summary &&
      other.finished == finished &&
      listEquals(other.ids, ids);

  @override
  int get hashCode => Object.hash(finished, Object.hashAll(ids));
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    required this.job,
    required this.onCancel,
    required this.onRetry,
  });

  final DownloadJob job;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final failed = job.phase == DownloadPhase.failed;
    final canRetry = failed || job.phase == DownloadPhase.cancelled;
    final canCancel =
        job.phase == DownloadPhase.waiting ||
        job.phase == DownloadPhase.downloading;
    final ok =
        job.phase == DownloadPhase.done || job.phase == DownloadPhase.duplicate;
    final title = job.tags.title ?? job.result.title;
    return Padding(
      key: ValueKey('download-row-${job.id}'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          OnlineImage(url: job.result.thumbnail, width: 44, height: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: c.text),
                ),
                const SizedBox(height: 2),
                Text(
                  downloadStatus(job),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: failed ? const Color(0xffff3b30) : c.muted,
                  ),
                ),
                if (job.phase == DownloadPhase.downloading) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: job.total > 0 ? job.received / job.total : null,
                      minHeight: 3,
                      color: c.accent,
                      backgroundColor: c.fill,
                    ),
                  ),
                ],
                if (canRetry)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRetry,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (canCancel)
            IconButton(
              key: const Key('download-cancel'),
              tooltip: 'Cancel',
              onPressed: onCancel,
              icon: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 22,
                color: c.faint,
              ),
            )
          else if (ok)
            Icon(
              CupertinoIcons.checkmark_circle_fill,
              size: 22,
              color: c.accent,
            )
          else if (failed)
            const Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              size: 22,
              color: Color(0xffff3b30),
            ),
        ],
      ),
    );
  }
}
