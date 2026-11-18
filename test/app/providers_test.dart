import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/track_repository.dart';
import 'package:owntune/settings/settings.dart';

import '../support/fakes.dart';

class FakeTrackRepository implements TrackRepository {
  FakeTrackRepository(this.tracks);

  final List<Track> tracks;

  @override
  Stream<List<Track>> watchAll() => Stream.value(tracks);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsRepository implements SettingsRepository {
  final saved = <AppSettings>[];

  @override
  Future<void> save(AppSettings s) async => saved.add(s);

  @override
  Future<AppSettings> load() async => AppSettings.defaults;
}

void main() {
  test('songsProvider sorts the tracks by title', () async {
    final container = ProviderContainer(
      overrides: [
        trackRepositoryProvider.overrideWithValue(
          FakeTrackRepository([
            track(1, title: 'Backroads'),
            track(2, originalName: 'demo_3.wav'),
            track(3, title: 'After the Rain'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Riverpod pauses providers without listeners.
    final sub = container.listen(songsProvider.future, (_, _) {});
    addTearDown(sub.close);
    final songs = await sub.read();
    expect([for (final s in songs) s.id], [3, 1, 2]);
  });

  test('settingsProvider starts with the startup settings', () {
    const stored = AppSettings(
      mode: AppearanceMode.light,
      accent: Color(0xff3ee0c4),
    );
    final container = ProviderContainer(
      overrides: [initialSettingsProvider.overrideWithValue(stored)],
    );
    addTearDown(container.dispose);
    expect(container.read(settingsProvider), stored);
  });

  test('SettingsNotifier.set updates the state and persists it', () async {
    final repo = FakeSettingsRepository();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    const next = AppSettings(
      mode: AppearanceMode.dark,
      accent: Color(0xffb38cff),
    );
    await container.read(settingsProvider.notifier).set(next);

    expect(container.read(settingsProvider), next);
    expect(repo.saved, [next]);
  });
}
