import 'package:owntune/data/db/database.dart';

/// The editable tag fields of a song, as stored in the database and written
/// into the file.
class TrackTags {
  const TrackTags({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.trackNumber,
    this.discNumber,
    this.year,
  });

  factory TrackTags.of(Track t) => TrackTags(
    title: t.title,
    artist: t.artist,
    album: t.album,
    albumArtist: t.albumArtist,
    genre: t.genre,
    trackNumber: t.trackNumber,
    discNumber: t.discNumber,
    year: t.year,
  );

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final int? trackNumber;
  final int? discNumber;
  final int? year;

  @override
  bool operator ==(Object other) =>
      other is TrackTags &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.albumArtist == albumArtist &&
      other.genre == genre &&
      other.trackNumber == trackNumber &&
      other.discNumber == discNumber &&
      other.year == year;

  @override
  int get hashCode => Object.hash(
    title,
    artist,
    album,
    albumArtist,
    genre,
    trackNumber,
    discNumber,
    year,
  );
}

enum TagField {
  title,
  artist,
  album,
  albumArtist,
  genre,
  track,
  disc,
  year;

  bool get isNumber => this == track || this == disc || this == year;

  Object? of(TrackTags t) => switch (this) {
    title => t.title,
    artist => t.artist,
    album => t.album,
    albumArtist => t.albumArtist,
    genre => t.genre,
    track => t.trackNumber,
    disc => t.discNumber,
    year => t.year,
  };
}

/// The text field [f] shows for [tracks]: the common value ('' when all are
/// empty), or null when the songs differ ("Mixed").
String? commonText(List<Track> tracks, TagField f) {
  String text(Track t) => '${f.of(TrackTags.of(t)) ?? ''}'.trim();
  final first = text(tracks.first);
  for (final t in tracks.skip(1)) {
    if (text(t) != first) return null;
  }
  return first;
}

/// The fields a user changed, as the text they typed; '' (or blank) clears
/// the field. Fields not in [changes] keep each song's own value.
class TagEdit {
  const TagEdit(this.changes);

  final Map<TagField, String> changes;

  bool get isEmpty => changes.isEmpty;

  TrackTags apply(TrackTags t) {
    String? text(TagField f, String? old) {
      if (!changes.containsKey(f)) return old;
      final v = changes[f]!.trim();
      return v.isEmpty ? null : v;
    }

    int? number(TagField f, int? old) {
      if (!changes.containsKey(f)) return old;
      final digits = changes[f]!.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.isEmpty ? null : int.parse(digits);
    }

    return TrackTags(
      title: text(TagField.title, t.title),
      artist: text(TagField.artist, t.artist),
      album: text(TagField.album, t.album),
      albumArtist: text(TagField.albumArtist, t.albumArtist),
      genre: text(TagField.genre, t.genre),
      trackNumber: number(TagField.track, t.trackNumber),
      discNumber: number(TagField.disc, t.discNumber),
      year: number(TagField.year, t.year),
    );
  }
}
