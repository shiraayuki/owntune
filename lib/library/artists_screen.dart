import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/search.dart';
import 'package:owntune/library/search_screen.dart';
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/library/songs_screen.dart';

String _count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

/// `2 albums · 18 songs`; the albums part is left out when there are none.
String artistCounts(Artist a) => [
  if (a.albums.isNotEmpty) _count(a.albums.length, 'album'),
  _count(a.songs.length, 'song'),
].join(' · ');

/// The Artists tab: one row per artist (mockup 08), or the empty state.
class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key});

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider).value;
    if (library == null) return const SizedBox.shrink();
    if (library.isEmpty) return const EmptyLibrary();
    final q = foldKey(_query.text);
    final artists = q.isEmpty
        ? library.artists
        : library.artists.where((a) => artistMatches(a, q)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabSearchField(label: 'Search Artists', controller: _query),
        Expanded(
          child: artists.isEmpty
              ? NoResults(query: _query.text)
              : _ArtistList(artists: artists),
        ),
      ],
    );
  }
}

class _ArtistList extends StatelessWidget {
  const _ArtistList({required this.artists});

  final List<Artist> artists;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      itemCount: artists.length,
      itemBuilder: (context, i) => LinkRow(
        leading: ArtistAvatar(artist: artists[i]),
        title: artists[i].name,
        subtitle: artistCounts(artists[i]),
        divider: i + 1 < artists.length,
        onTap: () => openArtist(context, artists[i].key, backLabel: 'Artists'),
      ),
    );
  }
}

/// 64pt row that opens a screen: 48pt [leading], title, subtitle and a
/// chevron.
class LinkRow extends StatelessWidget {
  const LinkRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.divider = true,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(CupertinoIcons.chevron_right, size: 18, color: c.faint),
                ],
              ),
            ),
            if (divider)
              Positioned(
                left: 60,
                right: 0,
                bottom: 0,
                child: Container(height: 0.5, color: c.line),
              ),
          ],
        ),
      ),
    );
  }
}

/// Round crop of the artist's [Artist.avatarCover], or a person icon.
class ArtistAvatar extends ConsumerWidget {
  const ArtistAvatar({super.key, required this.artist, this.size = 48});

  final Artist artist;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final cover = artist.avatarCover;
    final placeholder = ColoredBox(
      color: c.fill,
      child: Center(
        child: Icon(
          CupertinoIcons.person_fill,
          size: size * 0.5,
          color: c.muted,
        ),
      ),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: cover == null
            ? placeholder
            : Image.file(
                ref.watch(storageProvider).coverFile(cover),
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}
