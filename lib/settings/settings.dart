import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../data/db/database.dart';
import '../data/sources/online_source.dart';
import '../library/song_sort.dart';

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
  const AppSettings({
    required this.mode,
    required this.accent,
    this.songSort = SongSort.title,
    this.songSortDescending = false,
    this.onlineSource = OnlineSourceId.ytmusic,
    this.recentSearches = const [],
  });

  static const defaults = AppSettings(
    mode: AppearanceMode.system,
    accent: Color(0xffff7a59), // Coral
  );

  final AppearanceMode mode;
  final Color accent;

  /// Order of the Songs tab.
  final SongSort songSort;
  final bool songSortDescending;

  /// The last used segment of Search Online.
  final OnlineSourceId onlineSource;

  /// Search Online queries, newest first, at most [maxRecentSearches].
  final List<String> recentSearches;

  static const maxRecentSearches = 10;

  AppSettings copyWith({
    AppearanceMode? mode,
    Color? accent,
    SongSort? songSort,
    bool? songSortDescending,
    OnlineSourceId? onlineSource,
    List<String>? recentSearches,
  }) => AppSettings(
    mode: mode ?? this.mode,
    accent: accent ?? this.accent,
    songSort: songSort ?? this.songSort,
    songSortDescending: songSortDescending ?? this.songSortDescending,
    onlineSource: onlineSource ?? this.onlineSource,
    recentSearches: recentSearches ?? this.recentSearches,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.mode == mode &&
      other.accent == accent &&
      other.songSort == songSort &&
      other.songSortDescending == songSortDescending &&
      other.onlineSource == onlineSource &&
      listEquals(other.recentSearches, recentSearches);

  @override
  int get hashCode => Object.hash(
    mode,
    accent,
    songSort,
    songSortDescending,
    onlineSource,
    Object.hashAll(recentSearches),
  );
}

/// Persists [AppSettings] in the `settings_entries` key/value table.
/// Unknown or malformed stored values fall back to the defaults.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _appearanceKey = 'appearance';
  static const _accentKey = 'accent';
  static const _songSortKey = 'songs_sort';
  static const _songSortDescKey = 'songs_sort_desc';
  static const _onlineSourceKey = 'online_source';
  static const _onlineRecentKey = 'online_recent';
  static final _hex6 = RegExp(r'^[0-9a-f]{6}$');

  Future<AppSettings> load() async {
    final rows = await _db.select(_db.settingsEntries).get();
    final values = {for (final r in rows) r.key: r.value};
    return AppSettings(
      mode: _parseMode(values[_appearanceKey]),
      accent: _parseAccent(values[_accentKey]),
      songSort: SongSort.values.firstWhere(
        (s) => s.name == values[_songSortKey],
        orElse: () => AppSettings.defaults.songSort,
      ),
      songSortDescending: values[_songSortDescKey] == 'true',
      onlineSource: OnlineSourceId.values.firstWhere(
        (s) => s.name == values[_onlineSourceKey],
        orElse: () => AppSettings.defaults.onlineSource,
      ),
      recentSearches: _parseRecent(values[_onlineRecentKey]),
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
        SettingsEntriesCompanion.insert(
          key: _songSortKey,
          value: s.songSort.name,
        ),
        SettingsEntriesCompanion.insert(
          key: _songSortDescKey,
          value: '${s.songSortDescending}',
        ),
        SettingsEntriesCompanion.insert(
          key: _onlineSourceKey,
          value: s.onlineSource.name,
        ),
        SettingsEntriesCompanion.insert(
          key: _onlineRecentKey,
          value: jsonEncode(s.recentSearches),
        ),
      ]);
    });
  }

  static List<String> _parseRecent(String? v) {
    if (v == null) return const [];
    try {
      final list = jsonDecode(v);
      return list is List ? list.whereType<String>().toList() : const [];
    } on FormatException {
      return const [];
    }
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
