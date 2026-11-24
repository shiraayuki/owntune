import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/import/import_controller.dart';
import 'package:owntune/download/downloads_button.dart';
import 'package:owntune/download/search_online_screen.dart';
import 'package:owntune/import/import_sheets.dart';
import 'package:owntune/home/for_you.dart' show greeting;
import 'package:owntune/home/home_screen.dart';
import 'package:owntune/library/library_tab.dart';
import 'package:owntune/library/selection_bar.dart';
import 'package:owntune/library/search_screen.dart';
import 'package:owntune/library/song_sort.dart';
import 'package:owntune/player/mini_player.dart';
import 'package:owntune/player/player_controller.dart';
import 'package:owntune/player/system_controls.dart';
import 'package:owntune/playlists/new_playlist_sheet.dart';
import 'package:owntune/playlists/playlists_tab.dart';
import 'package:owntune/settings/settings.dart';
import 'package:owntune/settings/settings_sheet.dart';

/// Opens the settings; gets a context below the app's navigator. Defaults to
/// [showSettingsSheet].
typedef OpenSettings = void Function(BuildContext context);

class OwntuneApp extends ConsumerWidget {
  const OwntuneApp({super.key, this.onOpenSettings});

  final OpenSettings? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Lock screen / notification controls follow the player for the whole run.
    ref.watch(systemControlsSyncProvider);
    return MaterialApp(
      title: 'owntune',
      theme: buildTheme(Brightness.light, settings.accent),
      darkTheme: buildTheme(Brightness.dark, settings.accent),
      themeMode: switch (settings.mode) {
        AppearanceMode.system => ThemeMode.system,
        AppearanceMode.light => ThemeMode.light,
        AppearanceMode.dark => ThemeMode.dark,
      },
      // The import sheets sit above the navigator, so they also show over
      // pushed screens (album, artist, search).
      // The import sheets and the player's notices sit above the navigator,
      // so they also show over pushed screens and the full-screen player.
      builder: (context, child) => Stack(
        children: [child!, const _ImportLayer(), const _PlayerNotices()],
      ),
      home: AppShell(onOpenSettings: onOpenSettings),
    );
  }
}

/// [ImportOverlay] in an [Overlay] of its own: it sits above the
/// navigator, whose overlay selectable error text would otherwise need.
class _ImportLayer extends StatefulWidget {
  const _ImportLayer();

  @override
  State<_ImportLayer> createState() => _ImportLayerState();
}

class _ImportLayerState extends State<_ImportLayer> {
  final _entry = OverlayEntry(builder: (_) => const ImportOverlay());

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Positioned.fill(child: Overlay(initialEntries: [_entry]));
}

/// Shows the player's notices (e.g. a song that could not be played) as a
/// banner at the top, above every screen including the full-screen player.
/// It subscribes to the stream itself, so two equal notices in a row both
/// show, and it never takes taps.
class _PlayerNotices extends ConsumerStatefulWidget {
  const _PlayerNotices();

  @override
  ConsumerState<_PlayerNotices> createState() => _PlayerNoticesState();
}

class _PlayerNoticesState extends ConsumerState<_PlayerNotices> {
  static const _visibleFor = Duration(seconds: 3);

  StreamSubscription<String>? _sub;
  Timer? _hide;
  String? _text;
  var _visible = false;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(playerProvider.notifier).notices.listen((text) {
      _hide?.cancel();
      setState(() {
        _text = text;
        _visible = true;
      });
      _hide = Timer(_visibleFor, () {
        if (mounted) setState(() => _visible = false);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text == null) return const SizedBox.shrink();
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Center(
            child: Material(
              color: c.surface2,
              elevation: 8,
              shape: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: c.text),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _tabs = [
  _Tab('Home', CupertinoIcons.house, CupertinoIcons.house_fill),
  // These glyphs are already solid; there is no separate fill variant.
  _Tab('Search', CupertinoIcons.search, CupertinoIcons.search),
  _Tab(
    'Library',
    CupertinoIcons.square_stack,
    CupertinoIcons.square_stack_fill,
  ),
  _Tab(
    'Playlists',
    CupertinoIcons.music_note_list,
    CupertinoIcons.music_note_list,
  ),
];

/// Indexes of the Home and Library tabs in [_tabs].
const _homeTab = 0;
const _libraryTab = 2;

/// Title row with the "…" menu and "+", the four tabs and the tab bar. The
/// import sheets are added above the navigator by [OwntuneApp].
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.onOpenSettings});

  final OpenSettings? onOpenSettings;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  var _index = _homeTab;
  var _section = LibrarySection.songs;
  var _homeSection = HomeSection.forYou;

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(importControllerProvider) is ImportRunning;
    final selection = ref.watch(songSelectionProvider);
    final hasSongs =
        ref.watch(libraryProvider).value?.tracks.isNotEmpty ?? false;
    final onSongs = _index == _libraryTab && _section == LibrarySection.songs;
    return PopScope(
      // Back while selecting ends selection mode instead of leaving.
      canPop: selection == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(songSelectionProvider.notifier).end();
      },
      child: Scaffold(
        extendBody: true,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: _TitleRow(
                // The Home tab greets; screens opened from the title row get
                // the tab label as their back label, never the greeting.
                title: _index == _homeTab
                    ? greeting(ref.watch(clockProvider)())
                    : _tabs[_index].label,
                backLabel: _tabs[_index].label,
                selected: selection?.length,
                onDone: () => ref.read(songSelectionProvider.notifier).end(),
                showSort: onSongs,
                showSelect: onSongs && hasSongs,
                onSelect: () =>
                    ref.read(songSelectionProvider.notifier).start(),
                onOpenSettings: () =>
                    (widget.onOpenSettings ?? showSettingsSheet)(context),
                onImport: running
                    ? null
                    : () => ref
                          .read(importControllerProvider.notifier)
                          .pickAndImport(),
              ),
            ),
            Expanded(
              // The Builder's context sits below the Scaffold, so the bottom
              // padding the Scaffold adds for the tab bar (extendBody) is kept.
              child: Builder(
                builder: (context) => MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: IndexedStack(
                    index: _index,
                    children: [
                      HomeScreen(
                        section: _homeSection,
                        onSection: (s) => setState(() => _homeSection = s),
                      ),
                      const SearchTab(),
                      LibraryTab(
                        section: _section,
                        onSection: (s) {
                          ref.read(songSelectionProvider.notifier).end();
                          setState(() => _section = s);
                        },
                      ),
                      const PlaylistsTab(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: selection != null
            ? const SelectionBar()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MiniPlayer(overTabBar: true),
                  _TabBar(
                    index: _index,
                    onSelect: (i) => setState(() => _index = i),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 44pt row: large title inline with the round buttons (`.appbar`).
class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.backLabel,
    required this.selected,
    required this.onDone,
    required this.showSort,
    required this.showSelect,
    required this.onSelect,
    required this.onOpenSettings,
    required this.onImport,
  });

  final String title;

  /// What screens opened from the title row show as their back label.
  final String backLabel;

  /// How many songs are selected; null outside selection mode. While
  /// selecting, the title shows the count and "Done" replaces the buttons.
  final int? selected;
  final VoidCallback onDone;
  final bool showSort;
  final bool showSelect;
  final VoidCallback onSelect;
  final VoidCallback onOpenSettings;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Text(
                switch (selected) {
                  null => title,
                  0 => 'Select Songs',
                  final n => '$n Selected',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 34,
                  height: 44 / 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.68,
                  color: c.text,
                ),
              ),
            ),
            if (selected != null)
              _DonePill(onPressed: onDone)
            else ...[
              const DownloadsButton(),
              _MoreMenu(
                onOpenSettings: onOpenSettings,
                showSort: showSort,
                showSelect: showSelect,
                onSelect: onSelect,
              ),
              const SizedBox(width: 8),
              _AddMenu(
                key: const Key('import-button'),
                onImport: onImport,
                onSearchOnline: () =>
                    openSearchOnline(context, backLabel: backLabel),
                onNewPlaylist: () => showNewPlaylistSheet(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Done" of the title row in selection mode (`.glass` pill, accent text).
class _DonePill extends StatelessWidget {
  const _DonePill({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Material(
      key: const Key('selection-done'),
      color: c.fill,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                'Done',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Values of the "…" menu besides the sort orders ([SongSort]).
enum _MenuItem { ascending, descending, select, settings }

const _sortNames = {
  SongSort.title: 'Title',
  SongSort.artist: 'Artist',
  SongSort.album: 'Album',
  SongSort.added: 'Recently Added',
};

/// A 44pt pull-down menu row (`.menu .mi`); disabled rows are greyed out.
PopupMenuItem<Object> _menuItem(
  BuildContext context,
  Object value,
  String label, {
  IconData? icon,
  bool enabled = true,
  Key? key,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = dark ? const Color(0xffffffff) : const Color(0xff000000);
  final fg = enabled ? base : base.withValues(alpha: 0.35);
  return PopupMenuItem<Object>(
    key: key,
    value: value,
    enabled: enabled,
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17, color: fg),
          ),
        ),
        if (icon != null) ...[
          const SizedBox(width: 10),
          Icon(icon, size: 20, color: fg),
        ],
      ],
    ),
  );
}

/// Shared look of the "…" and "+" pull-down menus.
Color _menuColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color.fromRGBO(37, 37, 42, 0.96)
    : const Color.fromRGBO(250, 250, 250, 0.96);

enum _AddItem { playlist, import, online }

/// The "+" pull-down menu: New Playlist, Import Music (disabled while an
/// import runs) and Search Online.
class _AddMenu extends StatelessWidget {
  const _AddMenu({
    super.key,
    required this.onImport,
    required this.onSearchOnline,
    required this.onNewPlaylist,
  });

  final VoidCallback? onImport;
  final VoidCallback onNewPlaylist;
  final VoidCallback onSearchOnline;

  @override
  Widget build(BuildContext context) {
    return RoundIconSurface(
      tinted: true,
      child: PopupMenuButton<Object>(
        tooltip: 'Add',
        padding: EdgeInsets.zero,
        offset: const Offset(0, 52),
        color: _menuColor(context),
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        constraints: const BoxConstraints.tightFor(width: 250),
        menuPadding: EdgeInsets.zero,
        onSelected: (value) {
          if (value == _AddItem.playlist) onNewPlaylist();
          if (value == _AddItem.import) onImport?.call();
          if (value == _AddItem.online) onSearchOnline();
        },
        itemBuilder: (context) => [
          _menuItem(
            context,
            _AddItem.playlist,
            'New Playlist',
            key: const Key('menu-new-playlist'),
            icon: CupertinoIcons.music_note_list,
          ),
          _menuItem(
            context,
            _AddItem.import,
            'Import Music',
            key: const Key('menu-import'),
            icon: CupertinoIcons.square_arrow_down,
            enabled: onImport != null,
          ),
          _menuItem(
            context,
            _AddItem.online,
            'Search Online',
            key: const Key('menu-search-online'),
            icon: CupertinoIcons.globe,
          ),
        ],
        child: RoundIcon(icon: CupertinoIcons.plus, tinted: true),
      ),
    );
  }
}

/// The "…" pull-down menu: sort options (Songs tab only) and Settings.
class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({
    required this.onOpenSettings,
    required this.showSort,
    required this.showSelect,
    required this.onSelect,
  });

  final VoidCallback onOpenSettings;
  final bool showSort;

  /// "Select" (multi-select in Songs).
  final bool showSelect;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final settings = ref.watch(settingsProvider);

    PopupMenuItem<Object> item(Object value, String label, {IconData? icon}) =>
        _menuItem(context, value, label, icon: icon);
    IconData? check(bool on) => on ? CupertinoIcons.checkmark : null;

    return RoundIconSurface(
      child: PopupMenuButton<Object>(
        tooltip: 'More',
        padding: EdgeInsets.zero,
        offset: const Offset(0, 52),
        color: _menuColor(context),
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        constraints: const BoxConstraints.tightFor(width: 250),
        menuPadding: EdgeInsets.zero,
        onSelected: (value) {
          final notifier = ref.read(settingsProvider.notifier);
          final current = ref.read(settingsProvider);
          switch (value) {
            case final SongSort sort:
              notifier.set(current.copyWith(songSort: sort));
            case _MenuItem.ascending:
              notifier.set(current.copyWith(songSortDescending: false));
            case _MenuItem.descending:
              notifier.set(current.copyWith(songSortDescending: true));
            case _MenuItem.select:
              onSelect();
            case _MenuItem.settings:
              onOpenSettings();
          }
        },
        itemBuilder: (context) => [
          if (showSort) ...[
            PopupMenuItem<Object>(
              enabled: false,
              height: 32,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                'Sort By',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ),
            for (final MapEntry(key: sort, value: label) in _sortNames.entries)
              item(sort, label, icon: check(settings.songSort == sort)),
            menuGap(context),
            item(
              _MenuItem.ascending,
              'Ascending',
              icon: check(!settings.songSortDescending),
            ),
            item(
              _MenuItem.descending,
              'Descending',
              icon: check(settings.songSortDescending),
            ),
            menuGap(context),
          ],
          if (showSelect)
            item(
              _MenuItem.select,
              'Select',
              icon: CupertinoIcons.checkmark_circle,
            ),
          item(_MenuItem.settings, 'Settings', icon: CupertinoIcons.gear),
        ],
        child: const RoundIcon(icon: CupertinoIcons.ellipsis),
      ),
    );
  }
}

/// 49pt tab bar plus the home indicator area, translucent with blur.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(minHeight: 49 + bottom),
          padding: EdgeInsets.fromLTRB(8, 0, 8, bottom),
          decoration: BoxDecoration(
            color: dark
                ? const Color.fromRGBO(22, 22, 28, 0.82)
                : const Color.fromRGBO(251, 250, 247, 0.86),
            border: Border(top: BorderSide(color: c.line, width: 0.5)),
          ),
          // Own transparent Material: ink splashes of the tab items are
          // painted on it, above the bar's background, instead of on the
          // Scaffold's Material underneath.
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: _TabItem(
                      tab: _tabs[i],
                      selected: i == index,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final color = selected ? c.accent : c.muted;
    return Semantics(
      selected: selected,
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(top: 7, bottom: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  size: 26,
                  color: color,
                ),
                const SizedBox(height: 3),
                Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
