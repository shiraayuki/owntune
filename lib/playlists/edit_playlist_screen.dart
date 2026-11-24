import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/playlist_repository.dart';
import 'package:owntune/edit/cover_block.dart';
import 'package:owntune/edit/cover_flow.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/songs_screen.dart' show DialogAction;
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/playlists/playlist_artwork.dart';
import 'package:owntune/playlists/playlist_view.dart';

/// Opens the editor for [playlist] as a full-screen page above everything
/// (like Edit Info).
Future<void> openEditPlaylist(BuildContext context, PlaylistView playlist) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => EditPlaylistScreen(playlist: playlist),
      ),
    );

/// Edit Playlist (mockup 13): cover, name, and the songs with a remove
/// button and a drag handle each. Nothing is written until Done; Cancel
/// throws the draft away.
class EditPlaylistScreen extends ConsumerStatefulWidget {
  const EditPlaylistScreen({super.key, required this.playlist});

  /// The playlist as it was when the editor opened.
  final PlaylistView playlist;

  @override
  ConsumerState<EditPlaylistScreen> createState() => _EditPlaylistScreenState();
}

class _EditPlaylistScreenState extends ConsumerState<EditPlaylistScreen> {
  late final _name = TextEditingController(text: widget.playlist.name)
    ..addListener(() => setState(() {}));

  /// The songs as the user arranged them. Entries that left the library
  /// meanwhile are filtered out on use, see [_items].
  late List<PlaylistItem> _draft = widget.playlist.items;

  var _cover = const PlaylistCoverKeep() as PlaylistCoverChange;
  Uint8List? _preview;
  var _saving = false;

  /// A picked image is being decoded or cropped.
  var _processing = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  PlaylistView? get _current {
    for (final p in ref.read(playlistsProvider).value ?? const []) {
      if (p.id == widget.playlist.id) return p;
    }
    return null;
  }

  /// The draft without the entries whose song (or entry) is gone.
  List<PlaylistItem> get _items {
    final alive = {for (final i in _current?.items ?? const []) i.entryId};
    return [
      for (final i in _draft)
        if (alive.contains(i.entryId)) i,
    ];
  }

  bool get _canRemoveCover =>
      _cover is PlaylistCoverSet ||
      (_cover is PlaylistCoverKeep && _current?.coverFile != null);

  bool get _canSave => !_saving && !_processing && _name.text.trim().isNotEmpty;

  Future<void> _editCover() async {
    final action = await showCoverMenu(
      context,
      title: 'Playlist Cover',
      canRemove: _canRemoveCover,
    );
    if (action == null || !mounted) return;
    if (action == CoverAction.remove) {
      setState(() {
        _cover = const PlaylistCoverRemove();
        _preview = null;
      });
      return;
    }
    final data = await pickAndCropCover(
      context,
      ref.read(coverPickerProvider),
      action,
      onBusy: (busy) {
        if (mounted) setState(() => _processing = busy);
      },
    );
    if (data == null || !mounted) return;
    setState(() {
      _cover = PlaylistCoverSet(data);
      _preview = data;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    final items = _items;
    items.insert(newIndex, items.removeAt(oldIndex));
    setState(() => _draft = items);
  }

  void _remove(PlaylistItem item) => setState(
    () => _draft = [
      for (final i in _items)
        if (i.entryId != item.entryId) i,
    ],
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(playlistRepositoryProvider)
          .saveEdit(
            widget.playlist.id,
            name: _name.text.trim(),
            entryIds: [for (final i in _items) i.entryId],
            cover: _cover,
          );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showAdaptiveDialog<void>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: const Text("Couldn't save the playlist"),
          content: SelectableText('$e'),
          actions: [
            DialogAction(label: 'OK', onPressed: () => Navigator.pop(context)),
          ],
        ),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final async = ref.watch(playlistsProvider);
    final current = _current;
    if (current == null && async.hasValue) {
      // The playlist was deleted while editing; there is nothing to save to.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final route = ModalRoute.of(context);
        if (mounted && route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        }
      });
    }
    final items = _items;
    // What the cover shows now: the draft's songs for the mosaic, and no own
    // cover once it is removed or replaced by the preview.
    final shown = PlaylistView(
      id: widget.playlist.id,
      name: _name.text,
      coverFile: _cover is PlaylistCoverKeep ? current?.coverFile : null,
      createdAt: widget.playlist.createdAt,
      items: items,
    );

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  TextButton(
                    key: const Key('edit-playlist-cancel'),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    child: const Text('Cancel', style: TextStyle(fontSize: 17)),
                  ),
                  Expanded(
                    child: Text(
                      'Edit Playlist',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('edit-playlist-done'),
                    onPressed: _canSave ? _save : null,
                    style: TextButton.styleFrom(
                      foregroundColor: c.accent,
                      disabledForegroundColor: c.faint,
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, _, _) =>
                  Material(color: c.bg, elevation: 4, child: child),
              onReorderItem: _reorder,
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CoverTile(
                    playlist: shown,
                    preview: _preview,
                    busy: _processing,
                    onEdit: _saving || _processing ? null : _editCover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: dark ? c.surface2 : c.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: TextField(
                      key: const Key('edit-playlist-name'),
                      controller: _name,
                      enabled: !_saving,
                      style: TextStyle(fontSize: 17, color: c.text),
                      cursorColor: c.accent,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration.collapsed(
                        hintText: 'Name',
                        hintStyle: TextStyle(fontSize: 17, color: c.faint),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
                    child: Text(
                      '${items.length} ${items.length == 1 ? 'song' : 'songs'}'
                      ' · drag to reorder',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ),
                ],
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => _EditRow(
                key: ValueKey(items[i].entryId),
                item: items[i],
                index: i,
                enabled: !_saving,
                onRemove: () => _remove(items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 150pt cover and the "Edit Cover" pill; either one calls [onEdit].
class _CoverTile extends StatelessWidget {
  const _CoverTile({
    required this.playlist,
    required this.preview,
    required this.busy,
    required this.onEdit,
  });

  final PlaylistView playlist;
  final Uint8List? preview;
  final bool busy;
  final VoidCallback? onEdit;

  static const _side = 150.0;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 20),
      child: Column(
        children: [
          GestureDetector(
            onTap: onEdit,
            child: DecoratedBox(
              key: const Key('edit-playlist-cover'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x29000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PlaylistArtwork(
                    playlist: playlist,
                    size: _side,
                    preview: preview,
                    radius: 12,
                  ),
                  if (busy)
                    Container(
                      width: _side,
                      height: _side,
                      decoration: BoxDecoration(
                        color: const Color(0x66000000),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator.adaptive(
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: c.fill,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onEdit,
              child: SizedBox(
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.photo, size: 16, color: c.accent),
                      const SizedBox(width: 6),
                      Text(
                        'Edit Cover',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A song of the draft: red remove button, cover, title and artist, and the
/// handle that starts a drag.
class _EditRow extends ConsumerWidget {
  const _EditRow({
    super.key,
    required this.item,
    required this.index,
    required this.enabled,
    required this.onRemove,
  });

  final PlaylistItem item;
  final int index;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final red = dark ? const Color(0xffff453a) : const Color(0xffff3b30);
    final track = item.track;
    final cover = track.coverFile;
    final album = track.album?.trim();
    final subtitle = [
      displayArtist(track.artist),
      if (album != null && album.isNotEmpty) album,
    ].join(' · ');
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Remove ${displayTitle(track.title, track.originalName)}',
            excludeSemantics: true,
            child: GestureDetector(
              key: Key('edit-playlist-remove-${item.entryId}'),
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? onRemove : null,
              child: SizedBox(
                width: 40,
                height: 64,
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.minus,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Artwork(
            file: cover == null
                ? null
                : ref.watch(storageProvider).coverFile(cover),
            size: 48,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle(track.title, track.originalName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, color: c.text),
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
          ReorderableDragStartListener(
            key: Key('edit-playlist-handle-${item.entryId}'),
            index: index,
            enabled: enabled,
            child: SizedBox(
              width: 44,
              height: 64,
              child: Icon(
                CupertinoIcons.line_horizontal_3,
                size: 20,
                color: c.faint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
