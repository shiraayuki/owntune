import 'package:material_ui/material_ui.dart';

import '../data/db/database.dart';

enum AppearanceMode { system, light, dark }

class AccentPreset {
  const AccentPreset(this.name, this.color);

  final String name;
  final Color color;
}

const List<AccentPreset> kAccentPresets = [
  AccentPreset('Coral', Color(0xffff7a59)),
  AccentPreset('Amber', Color(0xffffb340)),
  AccentPreset('Lime', Color(0xffc6f432)),
  AccentPreset('Teal', Color(0xff3ee0c4)),
  AccentPreset('Sky', Color(0xff5ab4ff)),
  AccentPreset('Violet', Color(0xffb38cff)),
  AccentPreset('Pink', Color(0xffff6fb5)),
];

class AppSettings {
  const AppSettings({required this.mode, required this.accent});

  static const defaults = AppSettings(
    mode: AppearanceMode.system,
    accent: Color(0xffff7a59), // Coral
  );

  final AppearanceMode mode;
  final Color accent;

  AppSettings copyWith({AppearanceMode? mode, Color? accent}) =>
      AppSettings(mode: mode ?? this.mode, accent: accent ?? this.accent);

  @override
  bool operator ==(Object other) =>
      other is AppSettings && other.mode == mode && other.accent == accent;

  @override
  int get hashCode => Object.hash(mode, accent);
}

/// Persists [AppSettings] in the `settings_entries` key/value table.
/// Unknown or malformed stored values fall back to the defaults.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _appearanceKey = 'appearance';
  static const _accentKey = 'accent';
  static final _hex6 = RegExp(r'^[0-9a-f]{6}$');

  Future<AppSettings> load() async {
    final rows = await _db.select(_db.settingsEntries).get();
    final values = {for (final r in rows) r.key: r.value};
    return AppSettings(
      mode: _parseMode(values[_appearanceKey]),
      accent: _parseAccent(values[_accentKey]),
    );
  }

  Future<void> save(AppSettings s) async {
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.settingsEntries, [
        SettingsEntriesCompanion.insert(
          key: _appearanceKey,
          value: s.mode.name,
        ),
        SettingsEntriesCompanion.insert(key: _accentKey, value: _hex(s.accent)),
      ]);
    });
  }

  static AppearanceMode _parseMode(String? v) => AppearanceMode.values
      .firstWhere((m) => m.name == v, orElse: () => AppSettings.defaults.mode);

  static Color _parseAccent(String? v) {
    if (v == null || !_hex6.hasMatch(v)) return AppSettings.defaults.accent;
    return Color(0xff000000 | int.parse(v, radix: 16));
  }

  static String _hex(Color c) =>
      (c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0');
}
