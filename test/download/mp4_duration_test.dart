import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/mp4_duration.dart';

import '../support/mp4_boxes.dart';

void main() {
  const total = Duration(milliseconds: 188848);

  test('patches mvhd, tkhd and mdhd v0', () {
    final input = mp4();
    final out = patchMp4Duration(input, total);
    final v = view(out);
    // mvhd: header 8 + vf 4 + ctime 4 + mtime 4 + timescale 4 => duration.
    expect(v.getUint32(findBoxes(out, 'mvhd').single + 24), 188848);
    // tkhd: header 8 + vf 4 + ctime 4 + mtime 4 + id 4 + reserved 4.
    expect(v.getUint32(findBoxes(out, 'tkhd').single + 28), 188848);
    expect(v.getUint32(findBoxes(out, 'mdhd').single + 24), 8328197);
  });

  test('patches v1 boxes with 64-bit durations', () {
    const threeHours = Duration(hours: 3);
    final out = patchMp4Duration(
      mp4(traks: [trak(timescale: 1000000, v1: true)], v1: true),
      threeHours,
    );
    final v = view(out);
    // v1: header 8 + vf 4 + ctime 8 + mtime 8 + timescale 4.
    expect(v.getUint64(findBoxes(out, 'mvhd').single + 32), 10800 * 1000);
    // tkhd v1: header 8 + vf 4 + ctime 8 + mtime 8 + id 4 + reserved 4.
    expect(v.getUint64(findBoxes(out, 'tkhd').single + 36), 10800 * 1000);
    final mdhdDuration = v.getUint64(findBoxes(out, 'mdhd').single + 32);
    expect(mdhdDuration, 10800 * 1000000);
    expect(mdhdDuration, greaterThan(0xFFFFFFFF));
  });

  test('leaves every other byte unchanged', () {
    final input = mp4();
    final copy = Uint8List.fromList(input);
    final out = patchMp4Duration(input, total);
    expect(input, copy, reason: 'the input must not be modified');
    expect(out, hasLength(input.length));
    final fields = <int>{
      for (final o in [
        findBoxes(input, 'mvhd').single + 24,
        findBoxes(input, 'tkhd').single + 28,
        findBoxes(input, 'mdhd').single + 24,
      ])
        for (var i = 0; i < 4; i++) o + i,
    };
    for (var i = 0; i < input.length; i++) {
      if (fields.contains(i)) continue;
      expect(out[i], input[i], reason: 'byte $i changed');
    }
    expect(out, isNot(input));
  });

  test('patches each trak of a two-track moov', () {
    final out = patchMp4Duration(
      mp4(
        traks: [trak(timescale: 44100, id: 1), trak(timescale: 48000, id: 2)],
      ),
      total,
    );
    final v = view(out);
    final tkhds = findBoxes(out, 'tkhd');
    final mdhds = findBoxes(out, 'mdhd');
    expect(tkhds, hasLength(2));
    expect(mdhds, hasLength(2));
    for (final o in tkhds) {
      expect(v.getUint32(o + 28), 188848);
    }
    expect(v.getUint32(mdhds[0] + 24), 8328197);
    expect(v.getUint32(mdhds[1] + 24), 9064704); // 188.848 * 48000
  });

  test('throws on a truncated box', () {
    final input = mp4();
    final cut = Uint8List.sublistView(input, 0, input.length - 10);
    expect(
      () => patchMp4Duration(cut, total),
      throwsA(
        isA<OnlineError>().having(
          (e) => e.message,
          'message',
          "The stream's header could not be read",
        ),
      ),
    );
  });

  test('throws when there is no moov or no mvhd', () {
    for (final data in [
      box('ftyp', 'iso5'.codeUnits),
      Uint8List.fromList([
        ...box('ftyp', 'iso5'.codeUnits),
        ...box('moov', box('mvex', filler)),
      ]),
    ]) {
      expect(() => patchMp4Duration(data, total), throwsA(isA<OnlineError>()));
    }
  });
}
