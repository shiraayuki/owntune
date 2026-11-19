import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/library/artists_screen.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/library.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/search.dart';
import 'package:owntune/library/songs_screen.dart';
import 'package:owntune/library/sort_key.dart';

/// The rounded 36pt search box (`.search`).
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.search, size: 18, color: c.muted),
          const SizedBox(width: 6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The search field on the tabs: looks like a search box and opens the
/// global search when tapped.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _SearchBox(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17, color: c.muted),
          ),
        ),
      ),
    );
  }
}

/// Global search (mockup 10): results grouped into artists, albums and
/// songs; updates while typing and while the library changes.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final library = ref.watch(libraryProvider).value ?? Library.empty;
    final query = _controller.text;
    final results = searchLibrary(library, query);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _SearchBox(
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              cursorColor: c.accent,
                              style: TextStyle(fontSize: 17, color: c.text),
                              decoration: InputDecoration.collapsed(
                                hintText: 'Search',
                                hintStyle: TextStyle(
                                  fontSize: 17,
                                  color: c.muted,
                                ),
                              ),
                            ),
                          ),
                          if (query.isNotEmpty)
                            GestureDetector(
                              key: const Key('search-clear'),
                              behavior: HitTestBehavior.opaque,
                              onTap: _controller.clear,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  CupertinoIcons.xmark_circle_fill,
                                  size: 18,
                                  color: c.faint,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(fontSize: 17, color: c.accent),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _Results(query: query, results: results),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.results});

  final String query;
  final SearchResults results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    if (query.trim().isEmpty) return const SizedBox.shrink();
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(44, 40, 44, 0),
        child: Text(
          'No results for "${query.trim()}"',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, color: c.muted),
        ),
      );
    }
    final storage = ref.watch(storageProvider);
    const scope = SongMenuScope(backLabel: 'Search');
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        if (results.artists.isNotEmpty) ...[
          const _GroupHeader(title: 'Artists'),
          for (final (i, a) in results.artists.indexed)
            LinkRow(
              leading: ArtistAvatar(artist: a),
              title: a.name,
              subtitle: 'Artist',
              divider: i + 1 < results.artists.length,
              onTap: () => openArtist(context, a.key, backLabel: 'Search'),
            ),
        ],
        if (results.albums.isNotEmpty) ...[
          const _GroupHeader(title: 'Albums'),
          for (final (i, a) in results.albums.indexed)
            LinkRow(
              leading: Artwork(
                file: a.coverFile == null
                    ? null
                    : storage.coverFile(a.coverFile!),
              ),
              title: a.title,
              subtitle: 'Album · ${a.artist}',
              divider: i + 1 < results.albums.length,
              onTap: () => openAlbum(context, a.key, backLabel: 'Search'),
            ),
        ],
        if (results.songs.isNotEmpty) ...[
          const _GroupHeader(title: 'Songs'),
          for (final (i, t) in results.songs.indexed)
            SongRow(
              track: t,
              scope: scope,
              subtitle: 'Song · ${displayArtist(t.artist)}',
              divider: i + 1 < results.songs.length,
            ),
        ],
      ],
    );
  }
}

/// `.section-head` in the search results.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: c.accent,
        ),
      ),
    );
  }
}
