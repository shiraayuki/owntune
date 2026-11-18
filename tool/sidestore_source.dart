// Generates the SideStore/AltStore source (source.json) for a release.
//
// Usage (in the iOS workflow):
//   dart run tool/sidestore_source.dart <owner/repo> <tag> <build-number> <path/to.ipa>
import 'dart:convert';
import 'dart:io';

const _bundleId = 'dev.owntune.app';
const _minOS = '15.0';
const _iconPath =
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png';

Map<String, dynamic> buildSidestoreSource({
  required String repo,
  required String tag,
  required String buildNumber,
  required DateTime date,
  required int ipaSize,
}) {
  final match = RegExp(r'^v(\d+\.\d+\.\d+)$').firstMatch(tag);
  if (match == null) {
    throw ArgumentError.value(tag, 'tag', 'expected vX.Y.Z');
  }
  final releases = 'https://github.com/$repo/releases';
  return {
    'name': 'owntune',
    'identifier': 'dev.owntune.source',
    'sourceURL': '$releases/latest/download/source.json',
    'apps': [
      {
        'name': 'owntune',
        'bundleIdentifier': _bundleId,
        'developerName': 'owntune',
        'subtitle': 'Local music player',
        'localizedDescription':
            'Music player for local files – offline, no account.',
        'iconURL': 'https://raw.githubusercontent.com/$repo/main/$_iconPath',
        'versions': [
          {
            'version': match.group(1),
            'buildVersion': buildNumber,
            'date': date.toIso8601String().substring(0, 10),
            'downloadURL': '$releases/download/$tag/owntune.ipa',
            'size': ipaSize,
            'minOSVersion': _minOS,
          },
        ],
        'appPermissions': {'entitlements': <String>[], 'privacy': {}},
      },
    ],
    'news': <Object>[],
  };
}

void main(List<String> args) {
  if (args.length != 4) {
    stderr.writeln(
      'usage: dart run tool/sidestore_source.dart <owner/repo> <tag> <build> <ipa>',
    );
    exit(64);
  }
  final source = buildSidestoreSource(
    repo: args[0],
    tag: args[1],
    buildNumber: args[2],
    date: DateTime.now().toUtc(),
    ipaSize: File(args[3]).lengthSync(),
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(source));
}
