import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/placeholder_state.dart';

/// The Home tab. What goes here is decided once the rest of the app stands;
/// until then an empty state.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderState(
    icon: CupertinoIcons.house,
    title: 'Nothing here yet',
    message: 'Home arrives in a later version.',
  );
}
