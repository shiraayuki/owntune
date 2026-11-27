import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/update/app_version.dart';

/// GitHub's latest (not draft, not pre-release) release of owntune.
const kLatestReleaseApi =
    'https://api.github.com/repos/shiraayuki/owntune/releases/latest';

/// The signed APK of the latest release.
const kApkUrl =
    'https://github.com/shiraayuki/owntune/releases/latest/download/owntune.apk';

/// Opens SideStore, where an iPhone installs the update.
const kSideStoreUrl = 'sidestore://';

/// The download page, the fallback when SideStore does not open.
const kDownloadPageUrl = 'https://shiraayuki.github.io/owntune/';

/// The version of the latest release, or null when its tag is not a plain
/// `vX.Y.Z`. Network and HTTP errors propagate.
Future<AppVersion?> fetchLatestRelease(HttpTransport http) async {
  final json = await http.getJson(
    Uri.parse(kLatestReleaseApi),
    headers: const {'Accept': 'application/vnd.github+json'},
    service: 'GitHub',
  );
  final tag = json['tag_name'];
  return tag is String ? AppVersion.parse(tag) : null;
}
