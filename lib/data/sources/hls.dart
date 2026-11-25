import 'online_source.dart';

/// Parses an HLS media playlist of fragmented MP4 (an `#EXT-X-MAP` init
/// segment plus media segments) into the init URL and the segments.
///
/// Relative URIs resolve against [base]. A playlist that is encrypted fails
/// as protected; one that is a master playlist, is not complete (no
/// `#EXT-X-ENDLIST`), has no init segment or no segments fails as changed
/// ([service] names the site in the message), as does one that uses byte
/// ranges, a second init segment or discontinuities, which this parser would
/// get wrong. Nothing partial is returned.
({Uri init, List<HlsSegment> segments}) parseMediaPlaylist(
  String text,
  Uri base, {
  required String service,
}) {
  final lines = [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (lines.isEmpty || lines.first != '#EXTM3U') throw changedError(service);

  Uri? init;
  var ended = false;
  Duration? pending;
  final segments = <HlsSegment>[];

  for (final line in lines) {
    if (line.startsWith('#EXT-X-STREAM-INF') ||
        line.startsWith('#EXT-X-BYTERANGE') ||
        line == '#EXT-X-DISCONTINUITY') {
      throw changedError(service);
    }
    if (line.startsWith('#EXT-X-KEY:')) {
      final method = _attribute(line, 'METHOD');
      if (method != 'NONE') {
        throw const OnlineError("Protected: this track can't be downloaded");
      }
    } else if (line.startsWith('#EXT-X-MAP:')) {
      final uri = _attribute(line, 'URI');
      if (uri == null || init != null) throw changedError(service);
      init = base.resolve(uri);
    } else if (line.startsWith('#EXTINF:')) {
      final seconds = double.tryParse(
        line.substring('#EXTINF:'.length).split(',').first,
      );
      if (seconds == null) throw changedError(service);
      pending = Duration(microseconds: (seconds * 1e6).round());
    } else if (line == '#EXT-X-ENDLIST') {
      ended = true;
    } else if (!line.startsWith('#')) {
      if (pending == null) throw changedError(service);
      segments.add(HlsSegment(base.resolve(line), pending));
      pending = null;
    }
  }

  if (!ended || init == null || segments.isEmpty) throw changedError(service);
  return (init: init, segments: segments);
}

/// The value of [name] in a tag line like `#EXT-X-MAP:URI="x",BYTERANGE=…`,
/// without quotes; null when the attribute is missing.
String? _attribute(String line, String name) {
  final match = RegExp('(?:[:,])$name=("[^"]*"|[^,]*)').firstMatch(line);
  final value = match?.group(1);
  if (value == null) return null;
  return value.startsWith('"') ? value.substring(1, value.length - 1) : value;
}
