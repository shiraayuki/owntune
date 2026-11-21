import 'dart:io';
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/library/artwork.dart';

/// What the cover menu asks for.
enum CoverAction { photos, file, remove }

/// The cover at the top of Edit Info (`.cover-edit`): a 150pt square and an
/// "Edit Cover" pill; tapping either calls [onEdit].
///
/// Shows [preview] (a picked, not yet saved cover) if set, else "Mixed" when
/// the songs' covers differ, else [file] (null = the empty placeholder).
class CoverBlock extends StatelessWidget {
  const CoverBlock({
    super.key,
    required this.file,
    required this.mixed,
    required this.onEdit,
    this.preview,
    this.busy = false,
  });

  final File? file;
  final bool mixed;
  final Uint8List? preview;
  final VoidCallback? onEdit;

  /// A picked image is being processed: a spinner over the square.
  final bool busy;

  static const _side = 150.0;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final preview = this.preview;
    final Widget art;
    if (preview != null) {
      art = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          preview,
          width: _side,
          height: _side,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    } else if (mixed) {
      art = Container(
        width: _side,
        height: _side,
        decoration: BoxDecoration(
          color: c.fill,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text('Mixed', style: TextStyle(fontSize: 17, color: c.faint)),
      );
    } else {
      art = Artwork(file: file, size: _side, radius: 12);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 20),
      child: Column(
        children: [
          GestureDetector(
            onTap: onEdit,
            child: DecoratedBox(
              key: const Key('edit-cover-art'),
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
                  art,
                  if (busy)
                    Container(
                      key: const Key('edit-cover-busy'),
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

/// The cover action sheet: [title], Choose from Photos, Choose File,
/// Remove Cover (only if [canRemove]) and Cancel. Null when cancelled.
Future<CoverAction?> showCoverMenu(
  BuildContext context, {
  required String title,
  required bool canRemove,
}) => showModalBottomSheet<CoverAction>(
  context: context,
  useRootNavigator: true,
  backgroundColor: Colors.transparent,
  builder: (context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? c.surface2 : c.surface;
    final red = dark ? const Color(0xffff453a) : const Color(0xffff3b30);

    Widget row(
      String label,
      VoidCallback onTap, {
      Color? color,
      bool bold = false,
    }) => InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 57,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: color ?? c.accent,
            ),
          ),
        ),
      ),
    );
    Widget line() => Container(height: 0.5, color: c.line);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ),
                  line(),
                  row(
                    'Choose from Photos',
                    () => Navigator.pop(context, CoverAction.photos),
                  ),
                  line(),
                  row(
                    'Choose File',
                    () => Navigator.pop(context, CoverAction.file),
                  ),
                  if (canRemove) ...[
                    line(),
                    row(
                      'Remove Cover',
                      () => Navigator.pop(context, CoverAction.remove),
                      color: red,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: row('Cancel', () => Navigator.pop(context), bold: true),
            ),
          ],
        ),
      ),
    );
  },
);
