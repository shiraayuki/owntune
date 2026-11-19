import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';

/// Centered glyph, title and message for a tab whose content arrives in a
/// later version (Home, Playlists).
class PlaceholderState extends StatelessWidget {
  const PlaceholderState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        44,
        0,
        44,
        MediaQuery.paddingOf(context).bottom + 60,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: c.faint),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
