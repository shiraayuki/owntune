import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/import/import_controller.dart';
import 'package:owntune/import/import_sheets.dart';
import 'package:owntune/library/albums_screen.dart';
import 'package:owntune/library/artists_screen.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/search_screen.dart';
import 'package:owntune/library/song_sort.dart';
import 'package:owntune/library/songs_screen.dart';
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
      builder: (context, child) =>
          Stack(children: [child!, const _ImportLayer()]),
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

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _tabs = [
  // The note glyph is already solid; there is no separate fill variant.
  _Tab('Songs', CupertinoIcons.music_note, CupertinoIcons.music_note),
  _Tab('Albums', CupertinoIcons.square_stack, CupertinoIcons.square_stack_fill),
  _Tab('Artists', CupertinoIcons.person, CupertinoIcons.person_fill),
];

/// Title row with the "…" menu and "+", the three tabs and the tab bar. The
/// import sheets are added above the navigator by [OwntuneApp].
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.onOpenSettings});

  final OpenSettings? onOpenSettings;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(importControllerProvider) is ImportRunning;
    return Scaffold(
      extendBody: true,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: _TitleRow(
              title: _tabs[_index].label,
              showSort: _index == 0,
              onOpenSettings: () =>
                  (widget.onOpenSettings ?? showSettingsSheet)(context),
              onImport: running
                  ? null
                  : () => ref
                        .read(importControllerProvider.notifier)
                        .pickAndImport(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SearchField(
              label: 'Search ${_tabs[_index].label}',
              onTap: () => openSearch(context),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: IndexedStack(
                index: _index,
                children: const [
                  SongsScreen(),
                  AlbumsScreen(),
                  ArtistsScreen(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _TabBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// 44pt row: large title inline with the round buttons (`.appbar`).
class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.showSort,
    required this.onOpenSettings,
    required this.onImport,
  });

  final String title;
  final bool showSort;
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
                title,
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
            _MoreMenu(onOpenSettings: onOpenSettings, showSort: showSort),
            const SizedBox(width: 8),
            RoundIconButton(
              key: const Key('import-button'),
              icon: CupertinoIcons.plus,
              tooltip: 'Import Music',
              tinted: true,
              onPressed: onImport,
            ),
          ],
        ),
      ),
    );
  }
}

/// Values of the "…" menu besides the sort orders ([SongSort]).
enum _MenuItem { ascending, descending, settings }

const _sortNames = {
  SongSort.title: 'Title',
  SongSort.artist: 'Artist',
  SongSort.album: 'Album',
  SongSort.added: 'Recently Added',
};

/// The "…" pull-down menu: sort options (Songs tab only) and Settings.
class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.onOpenSettings, required this.showSort});

  final VoidCallback onOpenSettings;
  final bool showSort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final fg = dark ? const Color(0xffffffff) : const Color(0xff000000);
    final settings = ref.watch(settingsProvider);

    PopupMenuItem<Object> item(Object value, String label, {IconData? icon}) =>
        PopupMenuItem<Object>(
          value: value,
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
    IconData? check(bool on) => on ? CupertinoIcons.checkmark : null;

    return RoundIconSurface(
      child: PopupMenuButton<Object>(
        tooltip: 'More',
        padding: EdgeInsets.zero,
        offset: const Offset(0, 52),
        color: dark
            ? const Color.fromRGBO(37, 37, 42, 0.96)
            : const Color.fromRGBO(250, 250, 250, 0.96),
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
          padding: EdgeInsets.fromLTRB(30, 0, 30, bottom),
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
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _TabItem(
                    tab: _tabs[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
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
          width: 80,
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
