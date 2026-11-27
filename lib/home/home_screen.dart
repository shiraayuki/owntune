import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/text_tabs.dart';
import 'package:owntune/home/for_you_screen.dart';
import 'package:owntune/home/stats_screen.dart';
import 'package:owntune/update/update_banner.dart';

/// The sub-tabs of the Home tab, in display order.
enum HomeSection { forYou, stats }

const _labels = {HomeSection.forYou: 'For You', HomeSection.stats: 'Stats'};

/// For You | Stats under one tab, below the update banner when a newer
/// release is offered. Both stay mounted, so For You keeps its
/// scroll position. Unlike the Library tab, the text tabs stay visible with an
/// empty library.
///
/// A sub-tab that is not on screen (the other sub-tab, or Home not being the
/// selected tab) runs with its tickers off. Riverpod pauses the providers a
/// consumer watches while its [TickerMode] is off, so the hidden page's
/// history queries stop fetching during playback and catch up on return.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.section, required this.onSection});

  final HomeSection section;
  final ValueChanged<HomeSection> onSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const UpdateBanner(),
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
              _OnlyWhileVisible(child: ForYouScreen()),
              _OnlyWhileVisible(child: StatsScreen()),
            ],
          ),
        ),
      ],
    );
  }
}

/// Turns the tickers of [child] off while it is hidden. [Visibility.of]
/// combines every enclosing IndexedStack (the Home sub-tabs and the app's
/// tabs), and IndexedStack itself leaves the tickers on.
class _OnlyWhileVisible extends StatelessWidget {
  const _OnlyWhileVisible({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      TickerMode(enabled: Visibility.of(context), child: child);
}
