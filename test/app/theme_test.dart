import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/settings/settings.dart';

void main() {
  final sky = kAccentPresets.firstWhere((p) => p.name == 'Blue').color;

  OwntuneColors colors(ThemeData t) => t.extension<OwntuneColors>()!;

  test('light theme is Paper and ignores the accent', () {
    final theme = buildTheme(Brightness.light, sky);
    final c = colors(theme);
    expect(c.accent, c.text);
    expect(c.text, const Color(0xff16161a));
    expect(c.bg, const Color(0xfffbfaf7));
    expect(c.surface, const Color(0xffffffff));
    expect(c.surface2, const Color(0xfff1efea));
    expect(c.accentText, const Color(0xffffffff));
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, c.bg);
  });

  test('dark theme is Midnight and uses the accent', () {
    final theme = buildTheme(Brightness.dark, sky);
    final c = colors(theme);
    expect(c.accent, sky);
    expect(c.bg, const Color(0xff0e0e12));
    expect(c.surface, const Color(0xff1a1a21));
    expect(c.surface2, const Color(0xff24242d));
    expect(c.text, const Color(0xfff4f2ef));
    expect(c.accentText, const Color(0xff170b06));
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, sky);
    expect(theme.scaffoldBackgroundColor, c.bg);
  });

  test('translucent tokens match the mockup alpha values', () {
    final d = colors(buildTheme(Brightness.dark, sky));
    expect(d.fill, const Color.fromRGBO(120, 120, 128, 0.24));
    expect(d.line, const Color.fromRGBO(84, 84, 88, 0.6));
    expect(d.muted, const Color.fromRGBO(235, 235, 245, 0.6));
    expect(d.faint, const Color.fromRGBO(235, 235, 245, 0.3));
    final l = colors(buildTheme(Brightness.light, sky));
    expect(l.fill, const Color.fromRGBO(118, 118, 128, 0.12));
    expect(l.line, const Color.fromRGBO(60, 60, 67, 0.18));
    expect(l.muted, const Color.fromRGBO(60, 60, 67, 0.6));
    expect(l.faint, const Color.fromRGBO(60, 60, 67, 0.3));
  });

  test('OwntuneColors lerp and copyWith', () {
    final a = colors(buildTheme(Brightness.light, sky));
    final b = colors(buildTheme(Brightness.dark, sky));
    expect(a.lerp(b, 0).bg, a.bg);
    expect(a.lerp(b, 1).bg, b.bg);
    expect(a.copyWith(accent: sky).accent, sky);
  });
}
