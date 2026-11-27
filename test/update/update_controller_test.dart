import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/settings/settings.dart';
import 'package:owntune/update/app_version.dart';
import 'package:owntune/update/update_controller.dart';
import 'package:owntune/update/update_store.dart';

import '../support/fakes.dart';

const v0_11_0 = AppVersion(0, 11, 0);

void main() {
  late MemoryUpdateStore store;
  late FakeHttpTransport http;
  late String tag;
  late DateTime now;
  Object? failWith;
  Completer<void>? gate;

  setUp(() {
    store = MemoryUpdateStore();
    tag = 'v0.11.0';
    now = DateTime(2026, 11, 27, 10);
    failWith = null;
    gate = null;
    http = FakeHttpTransport(
      onGet: (url, headers) async {
        if (gate != null) await gate!.future;
        if (failWith != null) throw failWith!;
        return HttpBody(
          200,
          Stream.value(utf8.encode(jsonEncode({'tag_name': tag}))),
        );
      },
    );
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump();
    }
  }

  Future<ProviderContainer> start(
    WidgetTester t, {
    bool supported = true,
    String version = '0.10.0',
    String? buildNumber,
    bool checkForUpdates = true,
  }) async {
    // A release build's number follows its version (tool/release_version.sh).
    final v = AppVersion.parse(version)!;
    final build = buildNumber ?? '${v.major * 10000 + v.minor * 100 + v.patch}';
    final container = ProviderContainer(
      overrides: [
        updateCheckSupportedProvider.overrideWithValue(supported),
        updateStoreProvider.overrideWithValue(store),
        httpTransportProvider.overrideWithValue(http),
        appVersionProvider.overrideWith((ref) async => version),
        appBuildNumberProvider.overrideWith((ref) async => build),
        clockProvider.overrideWithValue(() => now),
        initialSettingsProvider.overrideWithValue(
          AppSettings.defaults.copyWith(checkForUpdates: checkForUpdates),
        ),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(updateControllerProvider, (_, _) {});
    await settle(t);
    return container;
  }

  Future<void> resume(WidgetTester t) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t);
  }

  UpdateInfo info(ProviderContainer c) => c.read(updateControllerProvider);

  testWidgets('first start checks and shows the banner', (t) async {
    final c = await start(t);
    expect(http.jsonGets, hasLength(1));
    expect(info(c).available, v0_11_0);
    expect(info(c).showBanner, isTrue);
    expect(store.record.lastCheck, now);
    expect(store.record.latest, v0_11_0);
  });

  testWidgets('within 24 h no second request', (t) async {
    store.record = UpdateRecord(
      lastCheck: now.subtract(const Duration(hours: 23)),
      latest: v0_11_0,
    );
    final c = await start(t);
    await resume(t);
    expect(http.jsonGets, isEmpty);
    expect(info(c).available, v0_11_0);
  });

  testWidgets('after 24 h resume checks again', (t) async {
    store.record = UpdateRecord(
      lastCheck: now.subtract(const Duration(hours: 1)),
      latest: v0_11_0,
    );
    await start(t);
    expect(http.jsonGets, isEmpty);
    now = now.add(const Duration(hours: 23));
    await resume(t);
    expect(http.jsonGets, hasLength(1));
  });

  testWidgets('a last check in the future is due', (t) async {
    store.record = UpdateRecord(lastCheck: now.add(const Duration(days: 3)));
    await start(t);
    expect(http.jsonGets, hasLength(1));
  });

  testWidgets('no update when the running version is the latest', (t) async {
    final c = await start(t, version: '0.11.0');
    expect(http.jsonGets, hasLength(1));
    expect(info(c).available, isNull);
    expect(info(c).showBanner, isFalse);
  });

  testWidgets('a running version newer than the release shows nothing', (
    t,
  ) async {
    final c = await start(t, version: '0.12.0');
    expect(info(c).available, isNull);
  });

  testWidgets('concurrent checks make one request', (t) async {
    gate = Completer<void>();
    final c = await start(t);
    final ctrl = c.read(updateControllerProvider.notifier);
    unawaited(ctrl.check(force: true));
    unawaited(ctrl.check(force: true));
    await resume(t);
    gate!.complete();
    await settle(t);
    expect(http.jsonGets, hasLength(1));
    expect(info(c).available, v0_11_0);
  });

  testWidgets('a failed check stores nothing and retries on resume', (t) async {
    failWith = const OnlineError('No connection');
    final c = await start(t);
    expect(http.jsonGets, hasLength(1));
    expect(info(c).showBanner, isFalse);
    expect(store.writes, 0);

    failWith = null;
    await resume(t);
    expect(http.jsonGets, hasLength(2));
    expect(info(c).showBanner, isTrue);
  });

  testWidgets('an odd tag stores nothing', (t) async {
    tag = 'v0.11.0-beta';
    final c = await start(t);
    expect(http.jsonGets, hasLength(1));
    expect(store.writes, 0);
    expect(info(c).available, isNull);
  });

  testWidgets('dismiss hides this version only', (t) async {
    final c = await start(t);
    await c.read(updateControllerProvider.notifier).dismiss();
    expect(info(c).showBanner, isFalse);
    expect(info(c).available, v0_11_0);
    expect(store.record.dismissed, v0_11_0);

    tag = 'v0.12.0';
    now = now.add(const Duration(hours: 24));
    await resume(t);
    expect(info(c).available, const AppVersion(0, 12, 0));
    expect(info(c).showBanner, isTrue);
  });

  testWidgets('a dismissed version stays dismissed after a restart', (t) async {
    store.record = UpdateRecord(
      lastCheck: now,
      latest: v0_11_0,
      dismissed: v0_11_0,
    );
    final c = await start(t);
    expect(info(c).available, v0_11_0);
    expect(info(c).showBanner, isFalse);
  });

  testWidgets('switch off hides, switch on checks at once', (t) async {
    final c = await start(t);
    expect(http.jsonGets, hasLength(1));
    final settings = c.read(settingsProvider.notifier);

    await settings.set(
      c.read(settingsProvider).copyWith(checkForUpdates: false),
    );
    await settle(t);
    expect(info(c).available, isNull);
    expect(info(c).showBanner, isFalse);
    await resume(t);
    expect(http.jsonGets, hasLength(1));

    await settings.set(
      c.read(settingsProvider).copyWith(checkForUpdates: true),
    );
    await settle(t);
    expect(http.jsonGets, hasLength(2));
    expect(info(c).showBanner, isTrue);
  });

  testWidgets('switched off at start makes no request', (t) async {
    final c = await start(t, checkForUpdates: false);
    await resume(t);
    expect(http.jsonGets, isEmpty);
    expect(info(c).available, isNull);
  });

  testWidgets('a build that is not a release build never asks', (t) async {
    // `flutter run` and manual workflow builds keep the pubspec's 0.7.0+1.
    final c = await start(t, version: '0.7.0', buildNumber: '1');
    await resume(t);
    expect(http.jsonGets, isEmpty);
    expect(info(c).available, isNull);
  });

  testWidgets('unsupported platform never asks', (t) async {
    final c = await start(t, supported: false);
    await resume(t);
    expect(http.jsonGets, isEmpty);
    expect(info(c).available, isNull);
  });
}
