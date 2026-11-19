import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';

/// Square cover thumbnail. The image is decoded at display size
/// (`cacheWidth`), so full-size embedded covers do not fill the memory.
/// Without a cover, or if the file cannot be read, a note icon is shown.
class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.file, this.size = 48, this.radius});

  final File? file;
  final double size;

  /// Corner radius; defaults to an eighth of [size].
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final placeholder = ColoredBox(
      color: c.fill,
      child: Center(
        child: Icon(
          CupertinoIcons.music_note,
          size: size * 0.46,
          color: c.muted,
        ),
      ),
    );
    final file = this.file;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size / 8),
      child: SizedBox.square(
        dimension: size,
        child: file == null
            ? placeholder
            : Image.file(
                file,
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
