import 'package:material_ui/material_ui.dart';

/// Color tokens from `docs/mockups/m1-v3/mockup.css`.
/// Light = Paper (monochrome), dark = Midnight (accent configurable).
@immutable
class OwntuneColors extends ThemeExtension<OwntuneColors> {
  const OwntuneColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.fill,
    required this.line,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentText,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color fill;
  final Color line;
  final Color text;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color accentText;

  /// Midnight. [accent] is the user's chosen accent preset.
  factory OwntuneColors.dark(Color accent) => OwntuneColors(
    bg: const Color(0xff0e0e12),
    surface: const Color(0xff1a1a21),
    surface2: const Color(0xff24242d),
    fill: const Color.fromRGBO(120, 120, 128, 0.24),
    line: const Color.fromRGBO(84, 84, 88, 0.6),
    text: const Color(0xfff4f2ef),
    muted: const Color.fromRGBO(235, 235, 245, 0.6),
    faint: const Color.fromRGBO(235, 235, 245, 0.3),
    accent: accent,
    accentText: const Color(0xff170b06),
  );

  /// Paper. The accent is the text color; the user's accent is ignored.
  static const light = OwntuneColors(
    bg: Color(0xfffbfaf7),
    surface: Color(0xffffffff),
    surface2: Color(0xfff1efea),
    fill: Color.fromRGBO(118, 118, 128, 0.12),
    line: Color.fromRGBO(60, 60, 67, 0.18),
    text: Color(0xff16161a),
    muted: Color.fromRGBO(60, 60, 67, 0.6),
    faint: Color.fromRGBO(60, 60, 67, 0.3),
    accent: Color(0xff16161a),
    accentText: Color(0xffffffff),
  );

  @override
  OwntuneColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? fill,
    Color? line,
    Color? text,
    Color? muted,
    Color? faint,
    Color? accent,
    Color? accentText,
  }) => OwntuneColors(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    fill: fill ?? this.fill,
    line: line ?? this.line,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    accent: accent ?? this.accent,
    accentText: accentText ?? this.accentText,
  );

  @override
  OwntuneColors lerp(OwntuneColors? other, double t) {
    if (other == null) return this;
    return OwntuneColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
      line: Color.lerp(line, other.line, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
    );
  }
}

ThemeData buildTheme(Brightness brightness, Color accent) {
  final c = brightness == Brightness.light
      ? OwntuneColors.light
      : OwntuneColors.dark(accent);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.line,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.accentText,
      secondary: c.accent,
      onSecondary: c.accentText,
      error: brightness == Brightness.light
          ? const Color(0xffff3b30)
          : const Color(0xffff453a),
      onError: const Color(0xffffffff),
      surface: c.surface,
      onSurface: c.text,
    ),
    extensions: [c],
  );
}
