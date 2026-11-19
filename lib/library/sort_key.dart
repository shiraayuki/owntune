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

/// Normalised key for matching: lowercase, trimmed and common Latin
/// diacritics folded.
String foldKey(String s) {
  final buffer = StringBuffer();
  for (final rune in s.trim().toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_folds[ch] ?? ch);
  }
  return buffer.toString();
}

/// Normalised key for sorting and grouping: [foldKey] with a leading "the "
/// removed.
String sortKey(String s) {
  var key = s.trim().toLowerCase();
  if (key.startsWith('the ')) key = key.substring(4).trimLeft();
  return foldKey(key);
}

bool _startsWithLetter(String key) {
  if (key.isEmpty) return false;
  final c = key.codeUnitAt(0);
  return c >= 0x61 && c <= 0x7a;
}

/// Compares two [sortKey] results. Keys that do not start with `a`-`z` (the
/// `#` section, including empty keys) sort after all letter keys.
int compareKeys(String a, String b) {
  final la = _startsWithLetter(a);
  final lb = _startsWithLetter(b);
  if (la != lb) return la ? -1 : 1;
  return a.compareTo(b);
}

/// `A`-`Z` for the first character of [sortKey], `#` for anything else.
String sectionLetter(String s) {
  final key = sortKey(s);
  if (!_startsWithLetter(key)) return '#';
  return String.fromCharCode(key.codeUnitAt(0) - 0x20);
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
