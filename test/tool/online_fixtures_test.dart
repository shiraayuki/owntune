import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _placeholder = 'CgtGSVhUVVJFVklTSVQ%3D';

/// Every visitor id in [node]: `visitorData` keys and `{"key":
/// "visitor_data", "value": …}` pairs (YouTube's tracking params).
Iterable<Object?> _visitorIds(Object? node) sync* {
  if (node is Map) {
    if (node.containsKey('visitorData')) yield node['visitorData'];
    if (node['key'] == 'visitor_data') yield node['value'];
    for (final v in node.values) {
      yield* _visitorIds(v);
    }
  } else if (node is List) {
    for (final v in node) {
      yield* _visitorIds(v);
    }
  }
}

/// The recorded YouTube responses are committed to a public repo: nothing
/// that identifies the recording session or network may be in them.
void main() {
  final files = Directory('test/fixtures/online')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'));

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final text = file.readAsStringSync();

    test('$name has no visitor id but the placeholder', () {
      expect(_visitorIds(jsonDecode(text)), everyElement(_placeholder));
    });

    test('$name has no googlevideo host or ip parameter', () {
      expect(text, isNot(contains('googlevideo')));
      expect(RegExp(r'[?&]ip=(?!0\.0\.0\.0)').hasMatch(text), isFalse);
    });
  }
}
