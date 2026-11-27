import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/update/app_version.dart';
import 'package:owntune/update/latest_release.dart';
import 'package:owntune/update/update_store.dart';

/// Whether this platform checks for updates at all: only the phones. Linux
/// is a dev aid whose pubspec version is not a release version; `pumpApp`
/// turns it off.
final updateCheckSupportedProvider = Provider<bool>(
  (ref) => Platform.isIOS || Platform.isAndroid,
);

final updateStoreProvider = Provider<UpdateStore>(
  (ref) => DbUpdateStore(ref.watch(databaseProvider)),
);

/// What the update check knows right now.
class UpdateInfo {
  const UpdateInfo({
    this.current,
    this.latest,
    this.dismissed,
    this.enabled = false,
  });

  /// The running version; null until known or when it does not parse.
  final AppVersion? current;

  /// The latest release found by the last successful check.
  final AppVersion? latest;

  /// The version whose banner the user closed.
  final AppVersion? dismissed;

  /// The Check for Updates switch.
  final bool enabled;

  /// The newer release to offer, or null.
  AppVersion? get available {
    final c = current, l = latest;
    return enabled && c != null && l != null && l > c ? l : null;
  }

  bool get showBanner => available != null && available != dismissed;
}

/// How long a successful check is good for.
const _checkInterval = Duration(hours: 24);

/// Asks GitHub for the latest release on start and whenever the app returns
/// to the foreground, at most once per [_checkInterval] after a successful
/// check. Failures stay silent and store nothing.
class UpdateController extends Notifier<UpdateInfo> {
  UpdateRecord _record = const UpdateRecord();
  AppVersion? _current;
  bool _ready = false;
  Future<void>? _running;

  @override
  UpdateInfo build() {
    if (!ref.watch(updateCheckSupportedProvider)) return const UpdateInfo();
    final lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
    ref.onDispose(lifecycle.dispose);
    ref.listen(settingsProvider.select((s) => s.checkForUpdates), (was, on) {
      _publish();
      if (on && was == false) unawaited(check(force: true));
    });
    unawaited(_init());
    return UpdateInfo(enabled: ref.read(settingsProvider).checkForUpdates);
  }

  Future<void> _init() async {
    try {
      _record = await ref.read(updateStoreProvider).read();
    } catch (_) {
      // A broken store only means no known state.
    }
    try {
      _current = AppVersion.parse(await ref.read(appVersionProvider.future));
    } catch (_) {
      // Without the running version nothing can be offered.
    }
    if (!ref.mounted) return;
    _ready = true;
    _publish();
    await check();
  }

  /// Checks now when due ([force] ignores the interval). Concurrent calls
  /// share one request.
  Future<void> check({bool force = false}) {
    if (!_ready || !ref.read(settingsProvider).checkForUpdates) {
      return Future.value();
    }
    return _running ??= _check(force).whenComplete(() => _running = null);
  }

  Future<void> _check(bool force) async {
    final now = ref.read(clockProvider)();
    final last = _record.lastCheck;
    final due =
        force ||
        last == null ||
        now.isBefore(last) ||
        now.difference(last) >= _checkInterval;
    if (!due) return;
    try {
      final latest = await fetchLatestRelease(ref.read(httpTransportProvider));
      if (latest == null || !ref.mounted) return;
      _record = UpdateRecord(
        lastCheck: now,
        latest: latest,
        dismissed: _record.dismissed,
      );
      _publish();
      await ref.read(updateStoreProvider).write(_record);
    } catch (_) {
      // No connection, an HTTP error or a changed answer: try next time.
    }
  }

  /// Hides the banner for the offered version; a newer one shows again.
  Future<void> dismiss() async {
    final offered = state.available;
    if (offered == null) return;
    _record = _record.copyWith(dismissed: offered);
    _publish();
    try {
      await ref.read(updateStoreProvider).write(_record);
    } catch (_) {
      // The banner stays hidden for this run.
    }
  }

  void _publish() {
    if (!ref.mounted) return;
    state = UpdateInfo(
      current: _current,
      latest: _record.latest,
      dismissed: _record.dismissed,
      enabled: ref.read(settingsProvider).checkForUpdates,
    );
  }
}

final updateControllerProvider = NotifierProvider<UpdateController, UpdateInfo>(
  UpdateController.new,
);
