import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/edit/cover_block.dart';
import 'package:owntune/edit/cover_flow.dart';
import 'package:owntune/library/songs_screen.dart' show DialogAction;

/// Opens the New Playlist sheet (mockup 15). Creates the playlist and then
/// adds [addTrackIds] to it; gives the new id, or null when cancelled or when
/// the songs couldn't be added (the playlist then exists, and the error was
/// shown).
Future<int?> showNewPlaylistSheet(
  BuildContext context, {
  List<int> addTrackIds = const [],
}) => showModalBottomSheet<int>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _NewPlaylistSheet(addTrackIds: addTrackIds),
);

class _NewPlaylistSheet extends ConsumerStatefulWidget {
  const _NewPlaylistSheet({required this.addTrackIds});

  final List<int> addTrackIds;

  @override
  ConsumerState<_NewPlaylistSheet> createState() => _NewPlaylistSheetState();
}

class _NewPlaylistSheetState extends ConsumerState<_NewPlaylistSheet> {
  final _name = TextEditingController();
  var _saving = false;

  /// A picked image is being decoded or cropped.
  var _processing = false;
  Uint8List? _preview;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      !_saving && !_processing && _name.text.trim().isNotEmpty;

  Future<void> _editCover() async {
    final action = await showCoverMenu(
      context,
      title: 'Playlist Cover',
      canRemove: _preview != null,
    );
    if (action == null || !mounted) return;
    if (action == CoverAction.remove) {
      setState(() => _preview = null);
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
    setState(() => _preview = data);
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    setState(() => _saving = true);
    final repo = ref.read(playlistRepositoryProvider);
    int id;
    try {
      id = await repo.create(_name.text, cover: _preview);
    } on Object catch (e) {
      await _showError("Couldn't create the playlist", '$e');
      return;
    }
    try {
      if (widget.addTrackIds.isNotEmpty) {
        await repo.addTracks(id, widget.addTrackIds);
      }
    } on Object catch (e) {
      // The playlist exists now; leaving the sheet open to retry would make a
      // twin. Closing with null tells the caller nothing was added.
      await _showError(
        "The playlist was created, but its songs couldn't be added",
        '$e',
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (mounted) Navigator.of(context).pop(id);
  }

  /// Shows [message] in a dialog and re-enables the sheet.
  Future<void> _showError(String title, String message) async {
    if (!mounted) return;
    await showAdaptiveDialog<void>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          DialogAction(label: 'OK', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final preview = _preview;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            MediaQuery.viewPaddingOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.faint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    TextButton(
                      key: const Key('new-playlist-cancel'),
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(foregroundColor: c.accent),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 17),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'New Playlist',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('new-playlist-create'),
                      onPressed: _canCreate ? _create : null,
                      style: TextButton.styleFrom(
                        foregroundColor: c.accent,
                        disabledForegroundColor: c.faint,
                      ),
                      child: const Text(
                        'Create',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: _CoverTile(
                  preview: preview,
                  busy: _processing,
                  onTap: _saving || _processing ? null : _editCover,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.fill,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: TextField(
                  key: const Key('new-playlist-name'),
                  controller: _name,
                  autofocus: true,
                  enabled: !_saving,
                  cursorColor: c.accent,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                  style: TextStyle(fontSize: 17, color: c.text),
                  decoration: InputDecoration.collapsed(
                    hintText: 'Playlist Name',
                    hintStyle: TextStyle(fontSize: 17, color: c.faint),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 7, 16, 0),
                child: Text(
                  'Without a cover, the playlist shows its first four albums.',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 120 pt cover square with the "Add Cover" pill (`.cover-edit`).
class _CoverTile extends StatelessWidget {
  const _CoverTile({
    required this.preview,
    required this.busy,
    required this.onTap,
  });

  final Uint8List? preview;
  final bool busy;
  final VoidCallback? onTap;

  static const _side = 120.0;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final preview = this.preview;
    return Column(
      children: [
        GestureDetector(
          key: const Key('new-playlist-cover'),
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: preview != null
                    ? Image.memory(
                        preview,
                        key: const Key('new-playlist-cover-preview'),
                        width: _side,
                        height: _side,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Container(
                        width: _side,
                        height: _side,
                        color: c.fill,
                        alignment: Alignment.center,
                        child: Icon(
                          CupertinoIcons.music_note_list,
                          size: 44,
                          color: c.muted,
                        ),
                      ),
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
        const SizedBox(height: 10),
        Material(
          color: c.fill,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
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
                      'Add Cover',
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
    );
  }
}
