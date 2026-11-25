import 'package:owntune/edit/track_tags.dart';

final _bracket = RegExp(r'\s*[(\[]([^()\[\]]*)[)\]]');
final _noise = RegExp(
  r'official|lyric|visuali[sz]er|\b(4k|hd|hq|mv)\b|upgrade|remaster|free\s*(dl|download)',
  caseSensitive: false,
);
final _keep = RegExp(
  r'live|acoustic|remix|feat|ft\.|version|edit|cover',
  caseSensitive: false,
);
final _separator = RegExp(r' [-–—] ');
final _spaces = RegExp(r'\s+');

/// Title and artist guessed from a YouTube video title, to prefill the
/// download sheet; the user corrects them there. The album stays empty.
TrackTags guessTags({required String videoTitle, required String channel}) {
  final cleaned = videoTitle
      .replaceAllMapped(_bracket, (m) {
        final inner = m[1]!;
        final drop = _noise.hasMatch(inner) && !_keep.hasMatch(inner);
        return drop ? '' : m[0]!;
      })
      .replaceAll(_spaces, ' ')
      .trim();
  final artistFromChannel = _cleanChannel(channel);

  final split = _separator.firstMatch(cleaned);
  if (split == null) {
    return TrackTags(
      title: cleaned,
      artist: artistFromChannel.isEmpty ? null : artistFromChannel,
    );
  }
  var artist = cleaned.substring(0, split.start).trim();
  var title = cleaned.substring(split.end).trim();
  if (title.toLowerCase() == artistFromChannel.toLowerCase()) {
    (artist, title) = (title, artist);
  }
  return TrackTags(title: title, artist: artist);
}

/// The channel name without " - Topic", "VEVO" and "Official".
String _cleanChannel(String channel) => channel
    .replaceAll(RegExp(r'\s*-\s*Topic$'), '')
    .replaceAll(RegExp(r'VEVO$'), '')
    .replaceAll(RegExp(r'^Official\s+|\s+Official$'), '')
    .trim();
