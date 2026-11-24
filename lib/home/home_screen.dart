import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/placeholder_state.dart';
import 'package:owntune/app/text_tabs.dart';
import 'package:owntune/home/for_you_screen.dart';

/// The sub-tabs of the Home tab, in display order.
enum HomeSection { forYou, stats }

const _labels = {HomeSection.forYou: 'For You', HomeSection.stats: 'Stats'};

/// For You | Stats under one tab. Both stay mounted, so For You keeps its
/// scroll position. Unlike the Library tab, the text tabs stay visible with an
/// empty library.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.section, required this.onSection});

  final HomeSection section;
  final ValueChanged<HomeSection> onSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextTabs<HomeSection>(
          key: const Key('home-segments'),
          segments: _labels,
          value: section,
          onChanged: onSection,
        ),
        Expanded(
          child: IndexedStack(
            index: section.index,
            children: const [
              ForYouScreen(),
              PlaceholderState(
                key: Key('stats-placeholder'),
                icon: CupertinoIcons.chart_bar,
                title: 'Stats are coming',
                message:
                    'Listening time, top artists and more arrive in the next '
                    'version.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
