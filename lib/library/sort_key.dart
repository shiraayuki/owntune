import 'package:owntune/data/db/database.dart';

const unknownArtist = 'Unknown Artist';

const _folds = <String, String>{
  'ä': 'a',
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ö': 'o',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ü': 'u',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ß': 'ss',
  'ç': 'c',
  'ñ': 'n',
};

/// Normalised key for sorting and grouping: lowercase, trimmed, leading
/// "the " removed and common Latin diacritics folded.
String sortKey(String s) {
  var key = s.trim().toLowerCase();
  if (key.startsWith('the ')) key = key.substring(4).trimLeft();
  final buffer = StringBuffer();
  for (final rune in key.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_folds[ch] ?? ch);
  }
  return buffer.toString();
}

/// `A`-`Z` for the first character of [sortKey], `#` for anything else.
String sectionLetter(String s) {
  final key = sortKey(s);
  if (key.isEmpty) return '#';
  final c = key.codeUnitAt(0);
  if (c >= 0x61 && c <= 0x7a) return String.fromCharCode(c - 0x20);
  return '#';
}

/// The title, or the original file name without extension when blank.
String displayTitle(String? title, String originalName) {
  final t = title?.trim();
  if (t != null && t.isNotEmpty) return t;
  final dot = originalName.lastIndexOf('.');
  return dot > 0 ? originalName.substring(0, dot) : originalName;
}

/// The artist, or `Unknown Artist` when missing or blank.
String displayArtist(String? artist) {
  final a = artist?.trim();
  return (a == null || a.isEmpty) ? unknownArtist : a;
}

/// Returns a new list sorted by title key, ties broken by artist key.
List<Track> sortByTitle(List<Track> tracks) {
  final keyed = [
    for (final t in tracks)
      (
        track: t,
        title: sortKey(displayTitle(t.title, t.originalName)),
        artist: sortKey(displayArtist(t.artist)),
      ),
  ];
  keyed.sort((a, b) {
    final c = a.title.compareTo(b.title);
    return c != 0 ? c : a.artist.compareTo(b.artist);
  });
  return [for (final k in keyed) k.track];
}
