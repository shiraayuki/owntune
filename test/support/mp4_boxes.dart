import 'dart:typed_data';

// Synthetic MP4 boxes for tests (a fragmented init segment with zero
// durations).

Uint8List u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();
Uint8List u64(int v) => (ByteData(8)..setUint64(0, v)).buffer.asUint8List();

/// An MP4 box with [type] and [payload].
Uint8List box(String type, List<int> payload) => Uint8List.fromList([
  ...u32(8 + payload.length),
  ...type.codeUnits,
  ...payload,
]);

const filler = [0xAA, 0xBB, 0xCC, 0xDD];

/// `mvhd`: version/flags, ctime, mtime, timescale, duration, then filler.
Uint8List mvhd({required int timescale, bool v1 = false}) => box('mvhd', [
  v1 ? 1 : 0,
  0,
  0,
  0,
  ...(v1 ? [...u64(1), ...u64(2)] : [...u32(1), ...u32(2)]),
  ...u32(timescale),
  ...(v1 ? u64(0) : u32(0)),
  ...filler,
]);

/// `tkhd`: version/flags, ctime, mtime, track id, reserved, duration, filler.
Uint8List tkhd({bool v1 = false, int id = 1}) => box('tkhd', [
  v1 ? 1 : 0,
  0,
  0,
  3,
  ...(v1 ? [...u64(1), ...u64(2)] : [...u32(1), ...u32(2)]),
  ...u32(id),
  ...u32(0),
  ...(v1 ? u64(0) : u32(0)),
  ...filler,
]);

Uint8List mdhd({required int timescale, bool v1 = false}) => box('mdhd', [
  v1 ? 1 : 0,
  0,
  0,
  0,
  ...(v1 ? [...u64(1), ...u64(2)] : [...u32(1), ...u32(2)]),
  ...u32(timescale),
  ...(v1 ? u64(0) : u32(0)),
  ...filler,
]);

Uint8List trak({required int timescale, bool v1 = false, int id = 1}) =>
    box('trak', [
      ...tkhd(v1: v1, id: id),
      ...box('mdia', [
        ...mdhd(timescale: timescale, v1: v1),
        ...box('hdlr', filler),
      ]),
    ]);

Uint8List mp4({
  int movieTimescale = 1000,
  List<Uint8List>? traks,
  bool v1 = false,
}) => Uint8List.fromList([
  ...box('ftyp', 'iso5'.codeUnits),
  ...box('moov', [
    ...mvhd(timescale: movieTimescale, v1: v1),
    ...(traks ?? [trak(timescale: 44100, v1: v1)]).expand((t) => t),
    ...box('mvex', filler),
    ...box('udta', filler),
  ]),
]);

/// Offsets of the boxes of [type] (the start of the 8-byte header).
List<int> findBoxes(Uint8List data, String type) {
  final out = <int>[];
  for (var i = 4; i + 4 <= data.length; i++) {
    if (String.fromCharCodes(data.sublist(i, i + 4)) == type) out.add(i - 4);
  }
  return out;
}

ByteData view(Uint8List d) => ByteData.sublistView(d);
