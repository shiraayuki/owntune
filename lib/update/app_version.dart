/// A release version `major.minor.patch`, compared as numbers.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(\+\d+)?$');

  /// Reads a release tag (`v0.11.0`) or an app version (`0.10.0`,
  /// `0.10.0+1000`); anything else (pre-release suffixes, other names) is
  /// null.
  static AppVersion? parse(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    return AppVersion(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  /// The build number a release of this version carries
  /// (`tool/release_version.sh`: 0.8.2 → 802).
  int get releaseBuildNumber => major * 10000 + minor * 100 + patch;

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
