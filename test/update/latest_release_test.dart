import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/update/app_version.dart';
import 'package:owntune/update/latest_release.dart';

import '../support/fakes.dart';

FakeHttpTransport answering(Object json, {int status = 200}) =>
    FakeHttpTransport(
      onGet: (url, headers) async =>
          HttpBody(status, Stream.value(utf8.encode(jsonEncode(json)))),
    );

void main() {
  test('reads the tag of the latest release', () async {
    final http = answering({'tag_name': 'v0.11.0', 'name': 'owntune v0.11.0'});
    expect(await fetchLatestRelease(http), const AppVersion(0, 11, 0));
    expect(http.jsonGets.single.url, Uri.parse(kLatestReleaseApi));
    expect(
      http.jsonGets.single.headers['Accept'],
      'application/vnd.github+json',
    );
  });

  test('a missing or odd tag is no version', () async {
    expect(await fetchLatestRelease(answering({'tag_name': 5})), isNull);
    expect(await fetchLatestRelease(answering(<String, Object?>{})), isNull);
    expect(
      await fetchLatestRelease(answering({'tag_name': 'v1.0.0-rc1'})),
      isNull,
    );
  });

  test('an HTTP error propagates', () async {
    expect(
      fetchLatestRelease(answering({'message': 'rate limit'}, status: 403)),
      throwsA(isA<HttpStatusError>()),
    );
  });

  test('the update links', () {
    expect(
      kLatestReleaseApi,
      'https://api.github.com/repos/shiraayuki/owntune/releases/latest',
    );
    expect(
      kApkUrl,
      'https://github.com/shiraayuki/owntune/releases/latest/download/owntune.apk',
    );
    expect(kSideStoreUrl, 'sidestore://');
    expect(kDownloadPageUrl, 'https://shiraayuki.github.io/owntune/');
  });
}
