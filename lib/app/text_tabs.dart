import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';

/// Text tabs (`.utabs` in the switch mockups): bold labels in a row, the
/// selected one in full color with a 3pt accent bar under it (inside the
/// label's 10pt bottom padding, as in the mockup), over a hairline.
/// Replaces the segmented control as the view switch.
class TextTabs<T> extends StatelessWidget {
  const TextTabs({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  /// Values and their labels, in display order.
  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(height: 0.5, color: c.line),
          ),
          // Scrolls sideways instead of overflowing at large text sizes.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, MapEntry(key: tab, value: label))
                    in segments.entries.indexed) ...[
                  if (i > 0) const SizedBox(width: 24),
                  _Tab(
                    label: label,
                    selected: tab == value,
                    onTap: () => onChanged(tab),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 7),
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: selected ? c.text : c.muted,
                  ),
                ),
              ),
              if (selected)
                Container(
                  key: const Key('text-tab-bar'),
                  height: 3,
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              else
                const SizedBox(height: 3),
            ],
          ),
        ),
      ),
    );
  }
}
