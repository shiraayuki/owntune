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
import 'package:owntune/player/player_controller.dart';

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

/// The search field of a tab (`.search`): a real text field that shows
/// "Cancel" while focused or filled; Cancel clears it and hides the
/// keyboard.
class TabSearchField extends StatefulWidget {
  const TabSearchField({
    super.key,
    required this.label,
    required this.controller,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;

  /// Called with the text when the keyboard's search key is pressed.
  final ValueChanged<String>? onSubmitted;

  @override
  State<TabSearchField> createState() => _TabSearchFieldState();
}

class _TabSearchFieldState extends State<TabSearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final controller = widget.controller;
    final active = _focus.hasFocus || controller.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: _SearchBox(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: widget.onSubmitted,
                      cursorColor: c.accent,
                      style: TextStyle(fontSize: 17, color: c.text),
                      decoration: InputDecoration.collapsed(
                        hintText: widget.label,
                        hintStyle: TextStyle(fontSize: 17, color: c.muted),
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty)
                    GestureDetector(
                      key: const Key('search-clear'),
                      behavior: HitTestBehavior.opaque,
                      onTap: controller.clear,
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
          if (active) ...[
            const SizedBox(width: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                controller.clear();
                _focus.unfocus();
              },
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: 17, color: c.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `No results for "<query>"`, shown by a filtered tab or the search.
class NoResults extends StatelessWidget {
  const NoResults({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 40, 44, 0),
      child: Text(
        'No results for "${query.trim()}"',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, color: c.muted),
      ),
    );
  }
}

/// The Search tab (mockup 10, as a tab): grouped results for artists,
/// albums and songs; updates while typing and while the library changes.
class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
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
    final library = ref.watch(libraryProvider).value ?? Library.empty;
    final query = _controller.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabSearchField(
          label: 'Artists, Albums, Songs',
          controller: _controller,
        ),
        Expanded(
          child: _Results(query: query, results: searchLibrary(library, query)),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.results});

  final String query;
  final SearchResults results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) return const SizedBox.shrink();
    if (results.isEmpty) return NoResults(query: query);
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
              onTap: () => ref
                  .read(playerProvider.notifier)
                  .playList(results.songs, start: i, source: 'Search'),
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
