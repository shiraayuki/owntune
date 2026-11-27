import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/update/latest_release.dart';
import 'package:url_launcher/url_launcher.dart';

/// Takes the user to the update: SideStore on iOS, the APK on Android.
abstract interface class UpdateLauncher {
  /// Never throws; a link that does not open is ignored.
  Future<void> open();
}

/// [UpdateLauncher] with url_launcher. iOS tries SideStore first and falls
/// back to the download page; Android opens the APK in the browser.
class PlatformUpdateLauncher implements UpdateLauncher {
  PlatformUpdateLauncher({
    required this.isIOS,
    Future<bool> Function(Uri url)? launch,
  }) : _launch = launch ?? _launchExternal;

  final bool isIOS;
  final Future<bool> Function(Uri url) _launch;

  static Future<bool> _launchExternal(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  Future<bool> _tryLaunch(String url) async {
    try {
      return await _launch(Uri.parse(url));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> open() async {
    if (!isIOS) {
      await _tryLaunch(kApkUrl);
    } else if (!await _tryLaunch(kSideStoreUrl)) {
      await _tryLaunch(kDownloadPageUrl);
    }
  }
}

final updateLauncherProvider = Provider<UpdateLauncher>(
  (ref) => PlatformUpdateLauncher(isIOS: Platform.isIOS),
);
