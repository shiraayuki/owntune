import 'package:owntune/library/library.dart';

/// Where a queue was started from.
enum QueueSourceKind {
  songs,
  album,
  artist,
  playlist,
  liked,
  search,
  queued,
  other,
}

/// The place a play queue came from: [kind] says what it is, [key] which one
/// (null for Songs, Liked Songs and Search) and [label] is shown in Up Next.
class QueueSource {
  const QueueSource(this.kind, this.label, {this.key});

  const QueueSource.songs() : this(QueueSourceKind.songs, 'Songs');

  QueueSource.album(AlbumKey key, String title)
    : this(
        QueueSourceKind.album,
        title,
        key: '${key.artist}\u0000${key.title}',
      );

  const QueueSource.artist(String key, String name)
    : this(QueueSourceKind.artist, name, key: key);

  QueueSource.playlist(int id, String name)
    : this(QueueSourceKind.playlist, name, key: '$id');

  const QueueSource.liked() : this(QueueSourceKind.liked, 'Liked Songs');

  const QueueSource.search() : this(QueueSourceKind.search, 'Search');

  final QueueSourceKind kind;
  final String? key;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is QueueSource &&
      other.kind == kind &&
      other.key == key &&
      other.label == label;

  @override
  int get hashCode => Object.hash(kind, key, label);

  @override
  String toString() => 'QueueSource($kind, $key, $label)';
}
