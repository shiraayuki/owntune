import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/player/queue_source.dart';

void main() {
  test('album key joins artist and title with NUL', () {
    final s = QueueSource.album((
      artist: 'juno vale',
      title: 'paper lanterns',
    ), 'Paper Lanterns');
    expect(s.key, 'juno vale\u0000paper lanterns');
    expect(s.label, 'Paper Lanterns');
    expect(s.kind, QueueSourceKind.album);
  });

  test('the other constructors set kind, key and label', () {
    expect(const QueueSource.songs().label, 'Songs');
    expect(const QueueSource.songs().kind, QueueSourceKind.songs);
    expect(const QueueSource.liked().label, 'Liked Songs');
    expect(const QueueSource.liked().kind, QueueSourceKind.liked);
    expect(const QueueSource.search().label, 'Search');
    expect(const QueueSource.search().kind, QueueSourceKind.search);
    final artist = const QueueSource.artist('juno vale', 'Juno Vale');
    expect(artist.kind, QueueSourceKind.artist);
    expect(artist.key, 'juno vale');
    expect(artist.label, 'Juno Vale');
    final playlist = QueueSource.playlist(7, 'Rainy Days');
    expect(playlist.kind, QueueSourceKind.playlist);
    expect(playlist.key, '7');
    expect(playlist.label, 'Rainy Days');
  });

  test('equality covers kind, key and label', () {
    expect(QueueSource.playlist(7, 'A'), QueueSource.playlist(7, 'A'));
    expect(
      QueueSource.playlist(7, 'A').hashCode,
      QueueSource.playlist(7, 'A').hashCode,
    );
    expect(QueueSource.playlist(7, 'A') == QueueSource.playlist(8, 'A'), false);
    expect(QueueSource.playlist(7, 'A') == QueueSource.playlist(7, 'B'), false);
    expect(
      const QueueSource.songs() ==
          const QueueSource(QueueSourceKind.other, 'Songs'),
      false,
    );
  });
}
