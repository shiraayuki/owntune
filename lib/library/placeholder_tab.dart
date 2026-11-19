import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/theme.dart';

/// A tab that ships in a later release.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: c.muted),
          ),
        ),
      ),
    );
  }
}
