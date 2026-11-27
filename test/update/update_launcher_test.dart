import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/update/latest_release.dart';
import 'package:owntune/update/update_launcher.dart';

void main() {
  late List<Uri> opened;

  Future<bool> Function(Uri) launching(bool Function(Uri) answer) =>
      (url) async {
        opened.add(url);
        return answer(url);
      };

  setUp(() => opened = []);

  test('iOS opens SideStore', () async {
    await PlatformUpdateLauncher(
      isIOS: true,
      launch: launching((_) => true),
    ).open();
    expect(opened, [Uri.parse(kSideStoreUrl)]);
  });

  test('iOS falls back to the download page', () async {
    await PlatformUpdateLauncher(
      isIOS: true,
      launch: launching((url) => url.scheme != 'sidestore'),
    ).open();
    expect(opened, [Uri.parse(kSideStoreUrl), Uri.parse(kDownloadPageUrl)]);
  });

  test('a throwing launch counts as not opened and never throws', () async {
    await PlatformUpdateLauncher(
      isIOS: true,
      launch: (url) async {
        opened.add(url);
        throw Exception('no handler');
      },
    ).open();
    expect(opened, [Uri.parse(kSideStoreUrl), Uri.parse(kDownloadPageUrl)]);
  });

  test('Android opens the APK', () async {
    await PlatformUpdateLauncher(
      isIOS: false,
      launch: launching((_) => true),
    ).open();
    expect(opened, [Uri.parse(kApkUrl)]);
  });
}
