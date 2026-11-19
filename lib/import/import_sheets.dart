import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/import/import_controller.dart';
import 'package:owntune/import/importer.dart';

String _count(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// Scrim plus the sheet for the current [ImportState]; empty while idle or
/// while a running import is hidden. Sits above the whole shell.
class ImportOverlay extends ConsumerWidget {
  const ImportOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final controller = ref.read(importControllerProvider.notifier);
    final Widget? sheet = switch (state) {
      ImportIdle() => null,
      ImportRunning(hidden: true) => null,
      ImportRunning(:final progress) => ImportProgressSheet(
        key: const ValueKey('progress'),
        progress: progress,
        onHide: controller.hide,
      ),
      ImportDone(:final summary) => ImportSummarySheet(
        key: const ValueKey('summary'),
        summary: summary,
        onDone: controller.dismiss,
      ),
      ImportFailed(:final message) => ImportFailedSheet(
        key: const ValueKey('failed'),
        message: message,
        onDone: controller.dismiss,
      ),
    };
    return Stack(
      children: [
        IgnorePointer(
          ignoring: sheet == null,
          child: ExcludeSemantics(
            excluding: sheet == null,
            child: AnimatedOpacity(
              opacity: sheet == null ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: const ModalBarrier(
                color: Color.fromRGBO(0, 0, 0, 0.55),
                dismissible: false,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOutCubic))
                  .animate(animation),
              child: child,
            ),
            child: sheet ?? const SizedBox.shrink(key: ValueKey('none')),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet frame of the import screens (`.isheet`).
class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      child: Material(
        color: dark ? const Color(0xff1c1c23) : const Color(0xffffffff),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line, width: 0.5),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            20 + math.max(media.viewPadding.bottom, 20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: c.faint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.subtitle);

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: TextStyle(fontSize: 15, color: c.muted)),
        ],
      ],
    );
  }
}

/// "Importing music…" with a progress bar and the current file.
class ImportProgressSheet extends StatelessWidget {
  const ImportProgressSheet({
    super.key,
    required this.progress,
    required this.onHide,
  });

  final ImportProgress progress;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final total = progress.total;
    return _Sheet(
      children: [
        _Heading(
          'Importing music…',
          '${progress.done} of ${_count(total, 'file')}',
        ),
        const SizedBox(height: 18),
        LinearProgressIndicator(
          value: total == 0 ? 0 : progress.done / total,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
          backgroundColor: c.fill,
          color: c.accent,
        ),
        const SizedBox(height: 8),
        Text(
          progress.currentName.isEmpty
              ? ''
              : 'Reading tags: ${progress.currentName}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: c.muted),
        ),
        const SizedBox(height: 24),
        PillButton(
          label: 'Hide – keep importing',
          secondary: true,
          expand: true,
          onPressed: onHide,
        ),
      ],
    );
  }
}

/// "Import complete" with added / duplicates / not supported.
class ImportSummarySheet extends StatelessWidget {
  const ImportSummarySheet({
    super.key,
    required this.summary,
    required this.onDone,
  });

  final ImportSummary summary;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = dark ? const Color(0xff30d158) : const Color(0xff34c759);
    final blue = dark ? const Color(0xff0a84ff) : const Color(0xff007aff);
    final orange = dark ? const Color(0xffff9f0a) : const Color(0xffff9500);

    final s = summary;
    final unsupported = s.unsupported;
    final hasOgg = unsupported.any((n) => n.toLowerCase().endsWith('.ogg'));
    return _Sheet(
      children: [
        _Heading('Import complete', '${_count(s.checked, 'file')} checked'),
        const SizedBox(height: 14),
        _ResultRow(
          icon: CupertinoIcons.checkmark,
          color: green,
          title: '${_count(s.added, 'song')} added',
          subtitle: s.added == 0
              ? null
              : '${_count(s.albums, 'album')} · ${_count(s.artists, 'artist')}',
        ),
        if (s.duplicates > 0)
          _ResultRow(
            icon: CupertinoIcons.doc_on_doc,
            color: blue,
            title: '${_count(s.duplicates, 'duplicate')} skipped',
            subtitle: 'Already in your library',
          ),
        if (unsupported.isNotEmpty)
          _ResultRow(
            icon: CupertinoIcons.exclamationmark_triangle,
            color: orange,
            title: '${_count(unsupported.length, 'file')} not supported',
            subtitle: [
              unsupported.join(', '),
              if (hasOgg) 'OGG is not supported yet',
            ].join(' · '),
          ),
        // Why supported files failed; selectable so it can be reported back
        // (there are no logs on the iPhone).
        for (final f in s.failures) _FailureReason('${f.name}: ${f.reason}'),
        const SizedBox(height: 18),
        PillButton(label: 'Done', expand: true, onPressed: onDone),
      ],
    );
  }
}

class _FailureReason extends StatelessWidget {
  const _FailureReason(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.only(left: 48, bottom: 6),
      child: SelectableText(
        text,
        style: TextStyle(fontSize: 13, color: c.muted),
      ),
    );
  }
}

/// Shown when the import as a whole failed (e.g. the library folder could
/// not be written).
class ImportFailedSheet extends StatelessWidget {
  const ImportFailedSheet({
    super.key,
    required this.message,
    required this.onDone,
  });

  final String message;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return _Sheet(
      children: [
        const _Heading('Import failed', null),
        const SizedBox(height: 8),
        SelectableText(message, style: TextStyle(fontSize: 15, color: c.muted)),
        const SizedBox(height: 18),
        PillButton(label: 'Done', expand: true, onPressed: onDone),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 15, color: c.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
