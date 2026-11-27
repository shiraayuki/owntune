import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/update/app_version.dart';

void main() {
  test('parses tags and plain versions', () {
    expect(AppVersion.parse('v0.11.0'), const AppVersion(0, 11, 0));
    expect(AppVersion.parse('0.10.0'), const AppVersion(0, 10, 0));
    expect(AppVersion.parse('0.10.0+1000'), const AppVersion(0, 10, 0));
    expect(AppVersion.parse(' v1.2.3 '), const AppVersion(1, 2, 3));
  });

  test('rejects anything else', () {
    for (final s in ['v0.11.0-beta', 'nightly', '0.11', '', 'v0.11.x']) {
      expect(AppVersion.parse(s), isNull, reason: s);
    }
  });

  test('a release build number follows the version', () {
    expect(const AppVersion(0, 8, 2).releaseBuildNumber, 802);
    expect(const AppVersion(1, 2, 3).releaseBuildNumber, 10203);
  });

  test('compares numerically, not as text', () {
    expect(const AppVersion(0, 10, 0) > const AppVersion(0, 9, 2), isTrue);
    expect(const AppVersion(1, 0, 0) > const AppVersion(0, 99, 99), isTrue);
    expect(const AppVersion(0, 10, 0) > const AppVersion(0, 10, 0), isFalse);
    expect(const AppVersion(0, 9, 2) > const AppVersion(0, 10, 0), isFalse);
    expect(const AppVersion(0, 11, 0).toString(), '0.11.0');
  });
}
