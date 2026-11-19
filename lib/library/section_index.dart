import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';

/// `A`–`Z` and `#`, in index order.
const indexLetters = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
];

const _bullet = '•';

/// The entries of an index strip with room for [slots] entries: all
/// [indexLetters] if they fit, otherwise evenly spaced letters (always `A`
/// and `#`) with a `•` wherever letters are left out.
List<String> collapseIndex(int slots) {
  if (slots >= indexLetters.length) return indexLetters;
  // k letters and k - 1 bullets.
  final k = ((slots + 1) ~/ 2).clamp(2, indexLetters.length);
  final last = indexLetters.length - 1;
  final entries = <String>[];
  var previous = -1;
  for (var j = 0; j < k; j++) {
    final i = (j * last / (k - 1)).round();
    if (previous >= 0 && i > previous + 1) entries.add(_bullet);
    entries.add(indexLetters[i]);
    previous = i;
  }
  return entries;
}

/// The letter a `•` at [i] in [entries] stands for: the first letter hidden
/// behind it.
String bulletTarget(List<String> entries, int i) =>
    indexLetters[indexLetters.indexOf(entries[i - 1]) + 1];

/// [letter] if it has a section, else the next letter in [indexLetters]
/// order that has one; `null` if none follows.
String? jumpTarget(String letter, Set<String> available) {
  for (final l in indexLetters.skip(indexLetters.indexOf(letter))) {
    if (available.contains(l)) return l;
  }
  return null;
}

/// The vertical A–Z strip at the right edge of the Songs list (`.index`).
/// Tapping or dragging calls [onSelect] with the letter under the finger.
class SectionIndex extends StatefulWidget {
  const SectionIndex({
    super.key,
    required this.available,
    required this.onSelect,
  });

  /// Letters that have a section; others are dimmed.
  final Set<String> available;
  final ValueChanged<String> onSelect;

  @override
  State<SectionIndex> createState() => _SectionIndexState();
}

class _SectionIndexState extends State<SectionIndex> {
  static const _slot = 14.0;
  String? _last;

  void _select(List<String> entries, double dy) {
    final i = (dy / _slot).floor().clamp(0, entries.length - 1);
    final letter = entries[i] == _bullet
        ? bulletTarget(entries, i)
        : entries[i];
    if (letter == _last) return;
    _last = letter;
    widget.onSelect(letter);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final entries = collapseIndex((constraints.maxHeight / _slot).floor());
        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              _last = null;
              _select(entries, d.localPosition.dy);
            },
            onVerticalDragStart: (d) {
              _last = null;
              _select(entries, d.localPosition.dy);
            },
            onVerticalDragUpdate: (d) => _select(entries, d.localPosition.dy),
            child: SizedBox(
              width: 22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in entries)
                    SizedBox(
                      height: _slot,
                      child: Center(
                        child: Text(
                          e,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            color: e == _bullet || widget.available.contains(e)
                                ? c.accent
                                : c.faint,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
