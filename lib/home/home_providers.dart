import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/home/for_you.dart';
import 'package:owntune/home/home_repository.dart';
import 'package:owntune/playlists/liked_songs.dart';

// Keyed by the start of the window: the stream stays the same within a day
// and switches to the new window when forYouProvider rebuilds after midnight.
final _recentSourcesProvider = StreamProvider.autoDispose
    .family<List<RecentSource>, DateTime>(
      (ref, since) =>
          ref.watch(homeRepositoryProvider).watchRecentSources(since: since),
    );

final _topTracksProvider = StreamProvider.autoDispose
    .family<List<TrackPlayCount>, DateTime>(
      (ref, since) =>
          ref.watch(homeRepositoryProvider).watchTopTracks(since: since),
    );

/// The content of For You. Loading until the library, the playlists, the
/// liked songs and the play history have values; an error if one of the first
/// three fails. A failing play history counts as empty, so Home works without
/// it.
///
/// The history windows are day-granular: recent sources of the last 365 days,
/// On Repeat of the last 30, both from local midnight. They move on the first
/// rebuild after midnight.
final forYouProvider = Provider<AsyncValue<ForYou>>((ref) {
  final library = ref.watch(libraryProvider);
  final playlists = ref.watch(playlistsProvider);
  final liked = ref.watch(likedSongsProvider);
  final now = ref.watch(clockProvider)();
  final recent = ref.watch(
    _recentSourcesProvider(DateTime(now.year, now.month, now.day - 365)),
  );
  final top = ref.watch(
    _topTracksProvider(DateTime(now.year, now.month, now.day - 30)),
  );
  for (final source in [library, playlists, liked]) {
    if (source.hasError) {
      return AsyncError(source.error!, source.stackTrace ?? StackTrace.empty);
    }
  }
  if (!library.hasValue || !playlists.hasValue || !liked.hasValue) {
    return const AsyncLoading();
  }
  for (final history in [recent, top]) {
    if (!history.hasValue && !history.hasError) return const AsyncLoading();
  }
  return AsyncData(
    buildForYou(
      library: library.requireValue,
      playlists: playlists.requireValue,
      liked: liked.requireValue,
      recent: recent.value ?? const [],
      topRecent: top.value ?? const [],
      now: now,
    ),
  );
});
