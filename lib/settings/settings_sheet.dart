import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoIcons, CupertinoSwitch;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/format.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/segmented.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/settings/settings.dart';
import 'package:owntune/update/update_controller.dart';
import 'package:owntune/update/update_launcher.dart';

export 'package:owntune/app/format.dart' show formatBytes;

/// Song count and storage used, read fresh each time the sheet opens.
final libraryStatsProvider =
    FutureProvider.autoDispose<({int songs, int bytes})>((ref) async {
      final repo = ref.watch(trackRepositoryProvider);
      return (songs: await repo.count(), bytes: await repo.storageBytes());
    });

/// Opens the settings as a modal sheet.
Future<void> showSettingsSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => const SettingsSheet(),
);

/// Settings per mockup v3 screen 11: appearance, accent, library, about.
class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final settings = ref.watch(settingsProvider);
    // Callbacks read the current state at tap time: two taps within one
    // frame must not overwrite each other with this build's snapshot.
    final notifier = ref.read(settingsProvider.notifier);
    final stats = ref.watch(libraryStatsProvider).value;
    final version = ref.watch(appVersionProvider).value;
    final update = ref.watch(updateControllerProvider).available;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Material(
      color: c.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 6, 16, math.max(bottom, 20) + 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: c.faint,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            _Header(onDone: () => Navigator.pop(context)),
            const _GroupLabel('Appearance'),
            Segmented<AppearanceMode>(
              segments: const {
                AppearanceMode.system: 'System',
                AppearanceMode.light: 'Light',
                AppearanceMode.dark: 'Dark',
              },
              value: settings.mode,
              onChanged: (m) =>
                  notifier.set(ref.read(settingsProvider).copyWith(mode: m)),
            ),
            const _GroupLabel('Accent Color · Dark Mode'),
            _Group(
              children: [
                _Swatches(
                  selected: settings.accent,
                  onSelect: (color) => notifier.set(
                    ref.read(settingsProvider).copyWith(accent: color),
                  ),
                ),
              ],
            ),
            const _GroupFoot('Light mode stays monochrome.'),
            const _GroupLabel('Playback'),
            _Group(
              children: [
                _SwitchCell(
                  key: const Key('normalize-volume'),
                  icon: CupertinoIcons.speaker_2,
                  label: 'Normalize Volume',
                  value: settings.normalizeVolume,
                  onChanged: (on) => notifier.set(
                    ref.read(settingsProvider).copyWith(normalizeVolume: on),
                  ),
                ),
              ],
            ),
            const _GroupFoot('Plays all songs at a similar loudness.'),
            const _GroupLabel('Library'),
            _Group(
              children: [
                _Cell(
                  icon: CupertinoIcons.floppy_disk,
                  label: 'Storage Used',
                  value: stats == null ? '' : formatBytes(stats.bytes),
                ),
                _Cell(
                  icon: CupertinoIcons.music_note,
                  label: 'Songs',
                  value: stats == null ? '' : '${stats.songs}',
                ),
              ],
            ),
            const _GroupLabel('About'),
            _Group(
              children: [
                _Cell(
                  icon: CupertinoIcons.info,
                  label: 'Version',
                  value: update == null
                      ? version ?? ''
                      : '${version ?? ''} · $update available',
                  onTap: update == null
                      ? null
                      : () => ref.read(updateLauncherProvider).open(),
                ),
                _SwitchCell(
                  key: const Key('check-updates'),
                  icon: CupertinoIcons.arrow_2_circlepath,
                  label: 'Check for Updates',
                  value: settings.checkForUpdates,
                  onChanged: (on) => notifier.set(
                    ref.read(settingsProvider).copyWith(checkForUpdates: on),
                  ),
                ),
              ],
            ),
            const _GroupFoot('Asks GitHub once a day for a new version.'),
          ],
        ),
      ),
    );
  }
}

/// `.sheet-head`: centered title, `Done` on the right.
class _Header extends StatelessWidget {
  const _Header({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onDone,
              style: TextButton.styleFrom(
                foregroundColor: c.accent,
                minimumSize: const Size(44, 44),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.group-label`: uppercase, muted, 13pt.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 7),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 13, letterSpacing: 0.26, color: c.muted),
      ),
    );
  }
}

class _GroupFoot extends StatelessWidget {
  const _GroupFoot(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
      child: Text(text, style: TextStyle(fontSize: 13, color: c.muted)),
    );
  }
}

/// `.group`: rounded box; cells are separated by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? c.surface2 : c.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Container(height: 0.5, color: c.line),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// `.cell`: gray badge, label and a muted value on the right.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Makes the row tappable; null leaves it a plain row.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final row = _CellRow(
      icon: icon,
      label: label,
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 17,
          color: onTap == null ? c.muted : c.accent,
        ),
      ),
    );
    return onTap == null
        ? row
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: row,
          );
  }
}

/// A [_Cell] with a switch instead of a value. The [key] goes on the switch.
class _SwitchCell extends StatelessWidget {
  const _SwitchCell({
    required Key key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  }) : _switchKey = key;

  final Key _switchKey;
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return _CellRow(
      icon: icon,
      label: label,
      trailing: CupertinoSwitch(
        key: _switchKey,
        value: value,
        activeTrackColor: c.accent,
        onChanged: onChanged,
      ),
    );
  }
}

/// Gray badge, label and [trailing], 44pt high.
class _CellRow extends StatelessWidget {
  const _CellRow({
    required this.icon,
    required this.label,
    required this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 29,
              height: 29,
              decoration: BoxDecoration(
                color: const Color(0xff8e8e93),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 18, color: const Color(0xffffffff)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 17, color: c.text)),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// The eight accent presets as 44pt circles; the selected one has a ring.
/// On screens narrower than 8 × 44pt (e.g. 360dp Android phones) the
/// circles shrink to fit instead of overflowing.
class _Swatches extends StatelessWidget {
  const _Swatches({required this.selected, required this.onSelect});

  final Color selected;
  final ValueChanged<Color> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = math.min(
            44.0,
            constraints.maxWidth / kAccentPresets.length,
          );
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final preset in kAccentPresets)
                Semantics(
                  label: preset.name,
                  button: true,
                  selected: preset.color == selected,
                  // Excluding the child's semantics drops the detector's tap
                  // action, so the node gets its own.
                  onTap: () => onSelect(preset.color),
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => onSelect(preset.color),
                    child: SizedBox.square(
                      dimension: size,
                      child: CustomPaint(
                        painter: _SwatchPainter(
                          color: preset.color,
                          ring: preset.color == selected ? c.text : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A filled circle and, when selected, a 2.5pt ring 4pt outside it (drawn
/// outside the 44pt box like the mockup's `inset: -4px`).
class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.color, this.ring});

  final Color color;
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(center, r, Paint()..color = color);
    if (ring != null) {
      canvas.drawCircle(
        center,
        r + 4 - 1.25,
        Paint()
          ..color = ring!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.ring != ring;
}
