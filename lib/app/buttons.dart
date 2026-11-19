import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';

/// Full-width or intrinsic 50pt button (`.btn` in the mockup).
/// [onPressed] null renders it disabled.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Gray fill with text color instead of the accent.
  final bool secondary;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final fg = secondary ? c.text : c.accentText;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: secondary ? c.fill : c.accent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// 44pt round button of the title row (`.glass` in the mockup).
/// [onPressed] null renders it disabled.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.tinted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Accent background (the "+" button).
  final bool tinted;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: RoundIconSurface(
      tinted: tinted,
      dimmed: onPressed == null,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: RoundIcon(icon: icon, tinted: tinted),
      ),
    ),
  );
}

/// The 44pt circle behind a [RoundIconButton], also used around a menu
/// button. It is its own [Material], so the tap feedback of the button inside
/// is painted on top of the fill instead of underneath it.
class RoundIconSurface extends StatelessWidget {
  const RoundIconSurface({
    super.key,
    required this.child,
    this.tinted = false,
    this.dimmed = false,
  });

  final Widget child;
  final bool tinted;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Opacity(
      opacity: dimmed ? 0.4 : 1,
      child: SizedBox.square(
        dimension: 44,
        child: Material(
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          color: tinted ? c.accent : c.fill,
          child: child,
        ),
      ),
    );
  }
}

/// The centered glyph of a [RoundIconSurface].
class RoundIcon extends StatelessWidget {
  const RoundIcon({super.key, required this.icon, this.tinted = false});

  final IconData icon;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return SizedBox.expand(
      child: Center(
        child: Icon(icon, size: 22, color: tinted ? c.accentText : c.text),
      ),
    );
  }
}
