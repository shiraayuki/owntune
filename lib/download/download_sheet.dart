import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/guess_tags.dart';
import 'package:owntune/download/online_image.dart';
import 'package:owntune/edit/track_tags.dart';

/// Opens the download sheet for [result] (mockup 09).
Future<void> showDownloadSheet(BuildContext context, OnlineResult result) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DownloadSheet(result: result),
    );

/// The tags a download starts with: the song's own (YouTube Music,
/// SoundCloud) or a guess from the video title (YouTube).
TrackTags suggestedTags(OnlineResult r) => r.source == OnlineSourceId.youtube
    ? guessTags(videoTitle: r.title, channel: r.channel ?? '')
    : r.tags;

/// "From YouTube Music · M4A, 128 kbps" and the like.
String sourceLine(OnlineResult r) => switch (r.source) {
  OnlineSourceId.ytmusic => 'From YouTube Music · M4A, 128 kbps',
  OnlineSourceId.youtube =>
    'From YouTube · "${r.title}"'
        '${r.channel == null ? '' : ' by ${r.channel}'} · M4A, 128 kbps',
  OnlineSourceId.soundcloud => 'From SoundCloud · M4A, ${r.kbps ?? 160} kbps',
};

/// Title, artist and album of a result, editable, and the Download button.
class DownloadSheet extends ConsumerStatefulWidget {
  const DownloadSheet({super.key, required this.result});

  final OnlineResult result;

  @override
  ConsumerState<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<DownloadSheet> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  late final TrackTags _suggested = suggestedTags(widget.result);
  var _sent = false;

  @override
  void initState() {
    super.initState();
    final tags = _suggested;
    _title = TextEditingController(text: tags.title ?? '')
      ..addListener(_changed);
    _artist = TextEditingController(text: tags.artist ?? '')
      ..addListener(_changed);
    _album = TextEditingController(text: tags.album ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  static String? _value(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _download() {
    if (_sent) return;
    _sent = true;
    ref
        .read(downloadControllerProvider.notifier)
        .enqueue(
          widget.result,
          // The three edited fields on top of the result's own tags, so the
          // genre and year SoundCloud knows survive.
          TrackTags(
            title: _value(_title),
            artist: _value(_artist),
            album: _value(_album),
            genre: _suggested.genre,
            year: _suggested.year,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final r = widget.result;
    final inLibrary = ref
        .watch(librarySourceKeysProvider)
        .contains(r.sourceKey);
    final canDownload = !inLibrary && _value(_title) != null && !_sent;
    final media = MediaQuery.of(context);
    final bottom = math.max(media.viewPadding.bottom, 20.0) + 16;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Material(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 6, 16, bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: c.faint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Center(
                child: OnlineImage(
                  url: r.squareCover
                      ? (r.coverUrl ?? r.thumbnail)
                      : r.thumbnail,
                  width: 120,
                  height: 120,
                  radius: 10,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _title.text.trim().isEmpty ? r.title : _title.text.trim(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              if (_artist.text.trim().isNotEmpty)
                Text(
                  _artist.text.trim(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: c.muted),
                ),
              const SizedBox(height: 8),
              Text(
                sourceLine(r),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.faint),
              ),
              const SizedBox(height: 18),
              _FieldGroup(
                children: [
                  _field(c, 'Title', 'download-title', _title),
                  _field(c, 'Artist', 'download-artist', _artist),
                  _field(c, 'Album', 'download-album', _album),
                ],
              ),
              const SizedBox(height: 20),
              PillButton(
                key: const Key('download-confirm'),
                label: inLibrary ? 'In Library' : 'Download',
                icon: inLibrary
                    ? CupertinoIcons.checkmark
                    : CupertinoIcons.arrow_down_to_line,
                expand: true,
                onPressed: canDownload ? _download : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    OwntuneColors c,
    String label,
    String key,
    TextEditingController controller,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: TextStyle(fontSize: 17, color: c.text)),
        ),
        Expanded(
          child: TextField(
            key: Key(key),
            controller: controller,
            textAlign: TextAlign.end,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            cursorColor: c.accent,
            style: TextStyle(fontSize: 17, color: c.text),
            decoration: const InputDecoration.collapsed(hintText: null),
          ),
        ),
      ],
    ),
  );
}

/// Rounded box of fields separated by hairlines (as in Edit Info).
class _FieldGroup extends StatelessWidget {
  const _FieldGroup({required this.children});

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
