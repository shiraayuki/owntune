import 'dart:typed_data';

import '../data/sources/online_source.dart';

/// Returns a copy of the MP4 init segment [init] with [total] written into
/// the duration of `mvhd` (movie timescale), every `tkhd` (movie timescale)
/// and every `mdhd` (that box's own timescale).
///
/// A fragmented MP4 keeps its durations in the fragments, so its header says
/// 0 and a tag reader would see an empty song. Handles versions 0 (32-bit)
/// and 1 (64-bit) of the boxes. Throws an [OnlineError] when `moov` or `mvhd`
/// is missing or a box runs past the end of the data.
Uint8List patchMp4Duration(Uint8List init, Duration total) {
  final out = Uint8List.fromList(init);
  final data = ByteData.sublistView(out);
  final micros = total.inMicroseconds;
  var movieTimescale = 0;
  var foundMvhd = false;

  void write(int offset, bool v1, int timescale) {
    final value = (micros * timescale / 1e6).round();
    if (v1) {
      data.setUint64(offset, value);
    } else {
      // All ones means "unknown" in a version 0 box; nothing longer fits.
      data.setUint32(offset, value > 0xFFFFFFFF ? 0xFFFFFFFF : value);
    }
  }

  void walk(int start, int end, List<String> path) {
    var pos = start;
    while (pos < end) {
      if (end - pos < 8) throw _unreadable();
      var size = data.getUint32(pos);
      final type = String.fromCharCodes(out.sublist(pos + 4, pos + 8));
      var header = 8;
      if (size == 1) {
        if (end - pos < 16) throw _unreadable();
        size = data.getUint64(pos + 8);
        header = 16;
      } else if (size == 0) {
        size = end - pos;
      }
      if (size < header || size > end - pos) throw _unreadable();
      final body = pos + header;
      final boxEnd = pos + size;
      final parent = path.isEmpty ? '' : path.last;

      if (parent == '' && type == 'moov' ||
          parent == 'moov' && type == 'trak' ||
          parent == 'trak' && type == 'mdia') {
        walk(body, boxEnd, [...path, type]);
      } else if (parent == 'moov' && type == 'mvhd') {
        final v1 = _version(data, body, boxEnd);
        // version/flags 4, then ctime and mtime, then timescale and duration.
        final timescaleAt = body + 4 + (v1 ? 16 : 8);
        _need(boxEnd, timescaleAt + 4 + (v1 ? 8 : 4));
        movieTimescale = data.getUint32(timescaleAt);
        write(timescaleAt + 4, v1, movieTimescale);
        foundMvhd = true;
      } else if (parent == 'trak' && type == 'tkhd') {
        final v1 = _version(data, body, boxEnd);
        // version/flags 4, ctime and mtime, track id 4, reserved 4, duration.
        final durationAt = body + 4 + (v1 ? 16 : 8) + 8;
        _need(boxEnd, durationAt + (v1 ? 8 : 4));
        // `mvhd` comes before the traks in a moov, so its timescale is known.
        write(durationAt, v1, movieTimescale);
      } else if (parent == 'mdia' && type == 'mdhd') {
        final v1 = _version(data, body, boxEnd);
        final timescaleAt = body + 4 + (v1 ? 16 : 8);
        _need(boxEnd, timescaleAt + 4 + (v1 ? 8 : 4));
        write(timescaleAt + 4, v1, data.getUint32(timescaleAt));
      }
      pos = boxEnd;
    }
  }

  walk(0, out.length, const []);
  if (!foundMvhd) throw _unreadable();
  return out;
}

bool _version(ByteData data, int body, int boxEnd) {
  _need(boxEnd, body + 4);
  return data.getUint8(body) == 1;
}

void _need(int boxEnd, int offset) {
  if (offset > boxEnd) throw _unreadable();
}

OnlineError _unreadable() =>
    const OnlineError("The stream's header could not be read");
