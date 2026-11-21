import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/edit/cover_block.dart';
import 'package:owntune/edit/cover_crop_screen.dart';
import 'package:owntune/edit/cover_image.dart';
import 'package:owntune/edit/tag_saver.dart';
import 'package:owntune/edit/track_tags.dart';
import 'package:owntune/library/songs_screen.dart' show DialogAction;
import 'package:owntune/library/sort_key.dart';
import 'package:owntune/player/player_controller.dart';

/// Opens the editor for [tracks] (one song, or several) as a full-screen
/// page above everything. True when the user saved (even if some songs
/// failed), false when cancelled.
Future<bool> openEditInfo(BuildContext context, List<Track> tracks) async =>
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => EditInfoScreen(tracks: tracks),
      ),
    ) ??
    false;

/// Edit Info: the tag fields of one song, or the shared fields of several.
/// In bulk, Title and Track are not offered, and a field whose value differs
/// between the songs shows "Mixed" and keeps each song's value unless typed
/// into.
class EditInfoScreen extends ConsumerStatefulWidget {
  const EditInfoScreen({super.key, required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<EditInfoScreen> createState() => _EditInfoScreenState();
}

const _labels = {
  TagField.title: 'Title',
  TagField.artist: 'Artist',
  TagField.album: 'Album',
  TagField.albumArtist: 'Album Artist',
  TagField.genre: 'Genre',
  TagField.year: 'Year',
  TagField.track: 'Track',
  TagField.disc: 'Disc',
};

// Top-level so the isolate closures capture only their arguments (a closure
// inside the State would try to send the whole widget tree).
Future<UprightCover?> _uprightInIsolate(Uint8List bytes) =>
    Isolate.run(() => uprightCover(bytes));

Future<Uint8List> _cropInIsolate(Uint8List bytes, Rect rect) =>
    Isolate.run(() => cropCover(bytes, rect));

const _maxDigits = {TagField.track: 3, TagField.disc: 3, TagField.year: 4};

class _EditInfoScreenState extends ConsumerState<EditInfoScreen> {
  late final bool _bulk = widget.tracks.length > 1;
  late final List<List<TagField>> _groups = [
    [
      if (!_bulk) TagField.title,
      TagField.artist,
      TagField.album,
      TagField.albumArtist,
    ],
    [TagField.genre, TagField.year],
    [if (!_bulk) TagField.track, TagField.disc],
  ];
  final _initial = <TagField, String>{};
  final _mixed = <TagField>{};
  final _controllers = <TagField, TextEditingController>{};
  var _saving = false;

  /// A picked image is being decoded or cropped (can take seconds for a big
  /// photo); the cover block shows a spinner and cannot be tapped.
  var _processing = false;
  late final _cover0 = commonCover(widget.tracks);

  /// The cover change so far; [_preview] holds the picked image of a
  /// [CoverSet].
  CoverEdit _cover = const CoverKeep();
  Uint8List? _preview;

  @override
  void initState() {
    super.initState();
    for (final f in _groups.expand((g) => g)) {
      final text = commonText(widget.tracks, f);
      if (text == null) _mixed.add(f);
      _initial[f] = text ?? '';
      _controllers[f] = TextEditingController(text: text ?? '')
        ..addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TagEdit get _edit => TagEdit({
    for (final MapEntry(key: f, value: c) in _controllers.entries)
      if (c.text != _initial[f]) f: c.text,
  }, cover: _cover);

  bool get _canRemoveCover =>
      _cover is CoverSet ||
      (_cover is CoverKeep && widget.tracks.any((t) => t.coverFile != null));

  Future<void> _editCover() async {
    final n = widget.tracks.length;
    final first = widget.tracks.first;
    final action = await showCoverMenu(
      context,
      title: _bulk
          ? 'Cover for $n songs'
          : 'Cover for “${displayTitle(first.title, first.originalName)}”',
      canRemove: _canRemoveCover,
    );
    if (action == null || !mounted) return;
    if (action == CoverAction.remove) {
      setState(() {
        _cover = const CoverRemove();
        _preview = null;
      });
      return;
    }
    final picker = ref.read(coverPickerProvider);
    final Uint8List? bytes;
    try {
      bytes = action == CoverAction.photos
          ? await picker.pickPhoto()
          : await picker.pickFile();
    } on Object catch (e) {
      if (mounted) await _showCoverError('$e');
      return;
    }
    if (bytes == null || !mounted) return;
    final Uint8List source = bytes;
    final upright = await _process(() => _uprightInIsolate(source));
    if (!mounted || upright == null) return;
    final image = upright.value;
    if (image == null) {
      await _showCoverError("This image can't be read. Choose a JPEG or PNG.");
      return;
    }
    final rect = await openCoverCrop(context, image);
    if (rect == null || !mounted) return;
    final data = await _process(() => _cropInIsolate(image.bytes, rect));
    if (!mounted || data == null) return;
    setState(() {
      _cover = CoverSet(data.value, 'image/jpeg');
      _preview = data.value;
    });
  }

  /// Runs [work] with the spinner on; any error is shown in a dialog (no
  /// logs on the iPhone) and gives null.
  Future<({T value})?> _process<T>(Future<T> Function() work) async {
    setState(() => _processing = true);
    try {
      return (value: await work());
    } on Object catch (e) {
      if (mounted) await _showCoverError('$e');
      return null;
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _showCoverError(String message) => showAdaptiveDialog<void>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: const Text("Couldn't use this image"),
      content: SelectableText(message),
      actions: [
        DialogAction(label: 'OK', onPressed: () => Navigator.pop(context)),
      ],
    ),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    List<SaveFailure> failures;
    try {
      failures = await ref.read(tagSaverProvider).save(widget.tracks, _edit);
    } on Object catch (e) {
      failures = [for (final t in widget.tracks) SaveFailure(t, '$e')];
    }
    if (!mounted) return;
    final failed = {for (final f in failures) f.track.id};
    await ref.read(playerProvider.notifier).reloadIfCurrent({
      for (final t in widget.tracks)
        if (!failed.contains(t.id)) t.id,
    });
    if (!mounted) return;
    if (failures.isNotEmpty) await _showFailures(failures);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _showFailures(List<SaveFailure> failures) {
    final n = failures.length;
    return showAdaptiveDialog<void>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text("Couldn't save $n ${n == 1 ? 'song' : 'songs'}"),
        content: SingleChildScrollView(
          child: SelectableText(
            [
              for (final f in failures)
                '${displayTitle(f.track.title, f.track.originalName)}: '
                    '${f.message}',
            ].join('\n'),
          ),
        ),
        actions: [
          DialogAction(label: 'OK', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final canSave = !_saving && !_processing && !_edit.isEmpty;
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
                    key: const Key('edit-cancel'),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    child: const Text('Cancel', style: TextStyle(fontSize: 17)),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Edit Info',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                        if (_bulk)
                          Text(
                            '${widget.tracks.length} Songs',
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const Key('edit-save'),
                    onPressed: canSave ? _save : null,
                    style: TextButton.styleFrom(
                      foregroundColor: c.accent,
                      disabledForegroundColor: c.faint,
                    ),
                    child: const Text(
                      'Save',
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
            child: ListView(
              // The iOS number pad has no key that closes it.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              children: [
                Center(
                  child: CoverBlock(
                    file: switch (_cover) {
                      CoverKeep() when _cover0.file != null =>
                        ref.watch(storageProvider).coverFile(_cover0.file!),
                      _ => null,
                    },
                    mixed: _cover is CoverKeep && _cover0.mixed,
                    preview: _preview,
                    busy: _processing,
                    onEdit: _saving || _processing ? null : _editCover,
                  ),
                ),
                for (final g in _groups)
                  if (g.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _Group(
                        children: [for (final f in g) _fieldRow(f, c)],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(TagField f, OwntuneColors c) {
    final max = _maxDigits[f];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 116,
            child: Text(
              _labels[f]!,
              style: TextStyle(fontSize: 17, color: c.text),
            ),
          ),
          Expanded(
            child: TextField(
              key: Key('edit-field-${f.name}'),
              controller: _controllers[f],
              enabled: !_saving,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 17, color: c.text),
              cursorColor: c.accent,
              keyboardType: f.isNumber ? TextInputType.number : null,
              textInputAction: TextInputAction.next,
              textCapitalization: f.isNumber
                  ? TextCapitalization.none
                  : TextCapitalization.words,
              inputFormatters: [
                if (max != null) ...[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(max),
                ],
              ],
              decoration: InputDecoration.collapsed(
                hintText: _mixed.contains(f) ? 'Mixed' : null,
                hintStyle: TextStyle(fontSize: 17, color: c.faint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded box of fields separated by hairlines (like the settings groups).
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? c.surface2 : c.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Container(height: 0.5, color: c.line),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}
