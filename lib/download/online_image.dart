import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';

/// A network image (result thumbnail or cover) with a music-note
/// placeholder while it loads or when it fails, cropped to its box.
class OnlineImage extends StatelessWidget {
  const OnlineImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.radius = 4,
  });

  final Uri url;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final placeholder = ColoredBox(
      color: c.fill,
      child: Center(
        child: Icon(
          CupertinoIcons.music_note,
          size: height * 0.42,
          color: c.muted,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.network(
          url.toString(),
          width: width,
          height: height,
          fit: BoxFit.cover,
          // By height: 16:9 thumbnails are also shown cropped in square boxes.
          cacheHeight: (height * MediaQuery.devicePixelRatioOf(context))
              .round(),
          gaplessPlayback: true,
          frameBuilder: (_, child, frame, sync) =>
              frame == null && !sync ? placeholder : child,
          errorBuilder: (_, _, _) => placeholder,
        ),
      ),
    );
  }
}
