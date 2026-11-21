import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';

import '../support/fakes.dart';

void main() {
  late StreamController<List<Track>> tracks;
  late ProviderContainer container;

  setUp(() {
    tracks = StreamController<List<Track>>();
    container = ProviderContainer(
      overrides: [tracksProvider.overrideWith((ref) => tracks.stream)],
    );
    container.listen(songSelectionProvider, (_, _) {});
  });

  tearDown(() {
    container.dispose();
    tracks.close();
  });

  test('starts empty, toggles, ends', () {
    final selection = container.read(songSelectionProvider.notifier);
    expect(container.read(songSelectionProvider), isNull);
    selection.start();
    expect(container.read(songSelectionProvider), <int>{});
    selection.toggle(1);
    selection.toggle(2);
    expect(container.read(songSelectionProvider), {1, 2});
    selection.toggle(1);
    expect(container.read(songSelectionProvider), {2});
    selection.end();
    expect(container.read(songSelectionProvider), isNull);
  });

  test('toggle does nothing while not selecting', () {
    container.read(songSelectionProvider.notifier).toggle(1);
    expect(container.read(songSelectionProvider), isNull);
  });

  test('drops ids of deleted songs', () async {
    tracks.add([track(1), track(2)]);
    await container.read(tracksProvider.future);
    final selection = container.read(songSelectionProvider.notifier)
      ..start()
      ..toggle(1)
      ..toggle(2);
    tracks.add([track(1)]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(songSelectionProvider), {1});
    selection.end();
  });
}
