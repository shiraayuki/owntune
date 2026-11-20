import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/app/providers.dart';

import '../support/fakes.dart';

void main() {
  test(
    'librarySourceKeysProvider lists the keys of downloaded tracks',
    () async {
      final container = ProviderContainer(
        overrides: [
          tracksProvider.overrideWith(
            (ref) => Stream.value([
              track(1, sourceKey: 'youtube:abc'),
              track(2),
              track(3, sourceKey: 'youtube:xyz'),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(librarySourceKeysProvider), isEmpty);
      container.listen(librarySourceKeysProvider, (_, _) {});
      await container.read(tracksProvider.future);
      expect(container.read(librarySourceKeysProvider), {
        'youtube:abc',
        'youtube:xyz',
      });
    },
  );
}
