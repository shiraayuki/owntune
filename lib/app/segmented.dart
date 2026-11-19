import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';

/// iOS-style segmented control (`.segmented` in the mockups): a 32pt track
/// with one raised segment for [value].
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.fontSize = 13,
  });

  /// Values and their labels, in display order.
  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (final MapEntry(key: segment, value: label) in segments.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: segment == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(segment),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    alignment: Alignment.center,
                    decoration: segment == value
                        ? BoxDecoration(
                            color: dark ? const Color(0xff636366) : c.surface,
                            borderRadius: BorderRadius.circular(7),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1f000000),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          )
                        : null,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: segment == value
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: c.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
