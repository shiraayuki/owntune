import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/home/stats_period.dart';
import 'package:owntune/home/stats_rankings.dart';
import 'package:owntune/home/stats_repository.dart';
import 'package:owntune/library/library.dart';

import '../support/fakes.dart';

const _min = 60000;

void main() {
  group('top lists', () {
    test('songs rank by plays then time', () {
      final library = Library.from([
        track(1, title: 'A', artist: 'X'),
        track(2, title: 'B', artist: 'Y'),
        track(3, title: 'C', artist: 'Z'),
      ]);
      final lists = buildTopLists(
        library: library,
        totals: const [
          TrackTotal(1, 4, 10 * _min),
          TrackTotal(2, 4, 30 * _min),
          TrackTotal(3, 1, 5 * _min),
        ],
      );
      expect(lists.songs.map((r) => r.title), ['B', 'A', 'C']);
      expect(lists.songs.map((r) => r.subtitle), ['Y', 'X', 'Z']);
      expect(lists.songs.map((r) => r.meter), [1.0, 1.0, 0.25]);
      expect(lists.songs.first.playsLabel, '4 plays');
      expect(lists.songs.last.playsLabel, '1 play');
      expect((lists.songs.first.target as SongTarget).track.id, 2);
    });

    test('artists group and show time', () {
      final library = Library.from([
        track(1, title: 'A', artist: 'Ann'),
        track(2, title: 'B', artist: 'ann '),
        track(3, title: 'C', artist: 'Bob'),
      ]);
      final lists = buildTopLists(
        library: library,
        totals: const [
          TrackTotal(1, 2, 20 * _min),
          TrackTotal(2, 1, 45 * _min),
          TrackTotal(3, 3, 3 * _min),
        ],
      );
      expect(lists.artists.map((r) => r.title), ['Ann', 'Bob']);
      expect(lists.artists.map((r) => r.plays), [3, 3]);
      // Equal plays: more time first.
      expect(lists.artists.first.subtitle, '1 h 05 min');
      expect(lists.artists.last.subtitle, '3 min');
      expect(lists.artists.first.meter, 1.0);
      expect((lists.artists.first.target as ArtistTarget).artist.name, 'Ann');
    });

    test('albums skip songs without an album', () {
      final library = Library.from([
        track(1, title: 'A', artist: 'X', album: 'Rec', albumArtist: 'Band'),
        track(2, title: 'B', artist: 'Y', album: 'rec', albumArtist: 'band'),
        track(3, title: 'C', artist: 'Z'),
        track(4, title: 'D', artist: 'Z', album: ' '),
      ]);
      final lists = buildTopLists(
        library: library,
        totals: const [
          TrackTotal(1, 1, _min),
          TrackTotal(2, 2, _min),
          TrackTotal(3, 9, _min),
          TrackTotal(4, 9, _min),
        ],
      );
      expect(lists.albums, hasLength(1));
      expect(lists.albums.single.title, 'Rec');
      expect(lists.albums.single.subtitle, 'Band');
      expect(lists.albums.single.plays, 3);
      expect(lists.albums.single.meter, 1.0);
      expect(lists.albums.single.target, isA<AlbumTarget>());
    });

    test('deleted songs count but never rank', () {
      final library = Library.from([
        track(1, title: 'A', artist: 'X', album: 'Rec', genre: 'Rock'),
      ]);
      const totals = [TrackTotal(1, 2, _min), TrackTotal(99, 7, 9 * _min)];
      final lists = buildTopLists(library: library, totals: totals);
      expect(lists.songs.map((r) => r.plays), [2]);
      expect(lists.artists.map((r) => r.plays), [2]);
      expect(lists.albums.map((r) => r.plays), [2]);
      final genres = buildGenres(
        library: library,
        totals: totals,
        period: StatsPeriod.week,
      )!;
      expect(genres.eyebrow, 'Genre mix · 9 plays this week');
      expect(genres.genres.map((g) => (g.name, g.plays)), [
        ('Unknown', 7),
        ('Rock', 2),
      ]);
    });

    test('renamed artist groups under the current name', () {
      // Both tracks now carry the new name; history only holds track ids.
      final library = Library.from([
        track(1, title: 'A', artist: 'New Name'),
        track(2, title: 'B', artist: 'New Name'),
      ]);
      final lists = buildTopLists(
        library: library,
        totals: const [TrackTotal(1, 1, _min), TrackTotal(2, 2, _min)],
      );
      expect(lists.artists, hasLength(1));
      expect(lists.artists.single.title, 'New Name');
      expect(lists.artists.single.plays, 3);
    });

    test('lists are capped at 50 and zero-play rows are skipped', () {
      final library = Library.from([
        for (var i = 1; i <= 60; i++) track(i, title: 'T$i', artist: 'A$i'),
      ]);
      final lists = buildTopLists(
        library: library,
        totals: [
          for (var i = 1; i <= 60; i++) TrackTotal(i, i, _min),
          const TrackTotal(61, 0, 1),
        ],
      );
      expect(lists.songs, hasLength(50));
      expect(lists.artists, hasLength(50));
      expect(lists.songs.first.plays, 60);
      final none = buildTopLists(
        library: library,
        totals: const [TrackTotal(1, 0, _min)],
      );
      expect(none.songs, isEmpty);
    });

    test('empty totals give empty lists with meter 0 safe', () {
      final lists = buildTopLists(library: Library.empty, totals: const []);
      expect(lists.songs, isEmpty);
      expect(lists.artists, isEmpty);
      expect(lists.albums, isEmpty);
    });
  });

  group('genres', () {
    test('genres fold case, top 4 plus Other, sum 100', () {
      final library = Library.from([
        track(1, genre: 'Rock'),
        track(2, genre: ' rock '),
        track(3, genre: 'Pop'),
        track(4, genre: 'Jazz'),
        track(5, genre: 'Folk'),
        track(6, genre: 'Soul'),
        track(7, genre: 'Punk'),
        track(8, genre: '  '),
      ]);
      final mix = buildGenres(
        library: library,
        totals: const [
          TrackTotal(1, 3, _min),
          TrackTotal(2, 5, _min),
          TrackTotal(3, 4, _min),
          TrackTotal(4, 3, _min),
          TrackTotal(5, 2, _min),
          TrackTotal(6, 1, _min),
          TrackTotal(7, 1, _min),
          TrackTotal(8, 1, _min),
        ],
        period: StatsPeriod.month,
      )!;
      expect(mix.eyebrow, 'Genre mix · 20 plays this month');
      expect(mix.genres.map((g) => g.name), [
        'rock', // 8 plays, spelling with most plays is ' rock ' trimmed
        'Pop',
        'Jazz',
        'Folk',
        'Other',
      ]);
      expect(mix.genres.map((g) => g.plays), [8, 4, 3, 2, 3]);
      expect(mix.genres.fold<int>(0, (a, g) => a + g.percent), 100);
    });

    test('display spelling is the one with most plays, first on a tie', () {
      final library = Library.from([
        track(1, genre: 'HIP HOP'),
        track(2, genre: 'Hip Hop'),
        track(3, genre: 'hip hop'),
      ]);
      final tie = buildGenres(
        library: library,
        totals: const [TrackTotal(1, 2, 1), TrackTotal(2, 2, 1)],
        period: StatsPeriod.year,
      )!;
      expect(tie.genres.single.name, 'HIP HOP');
      final won = buildGenres(
        library: library,
        totals: const [
          TrackTotal(1, 1, 1),
          TrackTotal(2, 1, 1),
          TrackTotal(3, 5, 1),
        ],
        period: StatsPeriod.allTime,
      )!;
      expect(won.genres.single.name, 'hip hop');
      expect(won.eyebrow, 'Genre mix · 7 plays all time');
    });

    test('Other is left out when nothing remains; null without plays', () {
      final library = Library.from([track(1, genre: 'Rock')]);
      final mix = buildGenres(
        library: library,
        totals: const [TrackTotal(1, 1, 1)],
        period: StatsPeriod.week,
      )!;
      expect(mix.genres.map((g) => g.name), ['Rock']);
      expect(mix.genres.single.percent, 100);
      expect(mix.eyebrow, 'Genre mix · 1 play this week');
      expect(
        buildGenres(
          library: library,
          totals: const [TrackTotal(1, 0, 5)],
          period: StatsPeriod.week,
        ),
        isNull,
      );
    });
  });

  group('recap', () {
    final now = DateTime(2026, 11, 24, 18);

    MonthRecap? recap({
      int monthMs = 125 * _min,
      int? previousMs = 80 * _min,
      int days = 5,
      List<TrackTotal> month = const [],
      Library? library,
      Map<int, ({DateTime first, int counted})> history = const {},
    }) => buildRecap(
      now: now,
      library: library ?? Library.empty,
      month: month,
      monthListenedMs: monthMs,
      monthDays: days,
      previousMonthListenedMs: previousMs,
      trackHistory: history,
    );

    test('recap caption variants', () {
      final more = recap()!;
      expect(more.eyebrow, 'Your November so far');
      expect(more.total, '2 h 05 min');
      expect(more.caption, 'listened in 5 days, 45 min more than October');
      expect(
        recap(monthMs: 20 * _min, previousMs: 85 * _min)!.caption,
        'listened in 5 days, 1 h 05 min less than October',
      );
      expect(
        recap(monthMs: 80 * _min, days: 1)!.caption,
        'listened in 1 day, same as October',
      );
      expect(recap(previousMs: null)!.caption, 'listened in 5 days');
      // Under a minute apart counts as the same, never "< 1 min more".
      expect(
        recap(monthMs: 80 * _min + 59999)!.caption,
        'listened in 5 days, same as October',
      );
      expect(
        recap(monthMs: 80 * _min - 59999)!.caption,
        'listened in 5 days, same as October',
      );
      expect(recap(monthMs: 0), isNull);
    });

    test('month names are full and the previous one wraps the year', () {
      final january = buildRecap(
        now: DateTime(2027, 1, 3),
        library: Library.empty,
        month: const [],
        monthListenedMs: _min,
        monthDays: 1,
        previousMonthListenedMs: 2 * _min,
        trackHistory: const {},
      )!;
      expect(january.eyebrow, 'Your January so far');
      expect(january.caption, 'listened in 1 day, 1 min less than December');
    });

    test('top song is the most played song still in the library', () {
      final library = Library.from([
        track(1, title: 'One', artist: 'X'),
        track(2, title: 'Two', artist: 'Y'),
      ]);
      final r = recap(
        library: library,
        month: const [
          TrackTotal(99, 50, _min),
          TrackTotal(1, 2, _min),
          TrackTotal(2, 3, _min),
        ],
      )!;
      expect(r.topSong!.title, 'Two');
      expect(r.topSong!.plays, 3);
      expect(r.topSong!.playsLabel, '3 plays');
      expect(recap()!.topSong, isNull);
    });

    test('new finds exclude songs with plays before the history', () {
      final library = Library.from([
        track(1, playCount: 5), // played before the history: 5 vs 2 counted
        track(2, playCount: 2), // first play this month, all in the history
        track(3, playCount: 1), // first play last month
        track(4, playCount: 1), // first play this month
        track(5, playCount: 1), // first play next year (never)
      ]);
      final r = recap(
        library: library,
        history: {
          1: (first: DateTime(2026, 11, 2), counted: 2),
          2: (first: DateTime(2026, 11, 10), counted: 2),
          3: (first: DateTime(2026, 10, 31, 23, 59), counted: 1),
          4: (first: DateTime(2026, 11, 1), counted: 1),
          6: (first: DateTime(2026, 11, 3), counted: 1), // deleted
        },
      )!;
      expect(r.newFinds, 2);
    });
  });

  group('library', () {
    test('library overview uses formatBytes, storage null while unknown', () {
      final library = Library.from([
        track(
          1,
          artist: 'X',
          album: 'A',
          albumArtist: 'B',
          durationMs: 90 * _min,
        ),
        track(
          2,
          artist: 'Y',
          album: 'A',
          albumArtist: 'B',
          durationMs: 40 * _min,
        ),
        track(3, artist: 'Y', durationMs: 5 * _min),
      ]);
      final o = buildLibraryOverview(
        library: library,
        playlistCount: 4,
        storageBytes: 431000000,
      );
      expect(o.songs, 3);
      expect(o.albums, 1);
      expect(o.artists, 2);
      expect(o.playlists, 4);
      expect(o.duration, '2 h 15 min');
      expect(o.storage, '411 MB');
      expect(
        buildLibraryOverview(
          library: library,
          playlistCount: 0,
          storageBytes: null,
        ).storage,
        isNull,
      );
    });

    test('most played top 5', () {
      final library = Library.from([
        track(1, title: 'a', playCount: 3, lastPlayedAt: DateTime(2026, 1, 1)),
        track(2, title: 'b', playCount: 3, lastPlayedAt: DateTime(2026, 2, 1)),
        track(3, title: 'c', playCount: 9, artist: 'Z'),
        track(4, title: 'd', playCount: 0),
        track(5, title: 'e', playCount: 1),
        track(6, title: 'f', playCount: 2),
        track(7, title: 'g', playCount: 4),
        track(8, title: 'h', playCount: 1),
      ]);
      final rows = buildMostPlayed(library);
      expect(rows.map((r) => r.title), ['c', 'g', 'b', 'a', 'f']);
      expect(rows.first.subtitle, 'Z');
      expect(rows.first.playsLabel, '9 plays');
      expect(rows.first.meter, 1.0);
      expect(rows[1].meter, closeTo(4 / 9, 1e-9));
      expect(buildMostPlayed(Library.empty), isEmpty);
    });
  });
}
