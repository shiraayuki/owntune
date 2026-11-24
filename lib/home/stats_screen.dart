import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/home/for_you_screen.dart';
import 'package:owntune/home/home_cards.dart' show homeBackLabel;
import 'package:owntune/home/stats_list_screen.dart';
import 'package:owntune/home/stats_listening.dart';
import 'package:owntune/home/stats_period.dart';
import 'package:owntune/home/stats_providers.dart';
import 'package:owntune/home/stats_rankings.dart';
import 'package:owntune/library/artwork.dart';
import 'package:owntune/library/songs_screen.dart' show LoadError;

const _chipLabels = {
  StatsPeriod.week: 'Week',
  StatsPeriod.month: 'Month',
  StatsPeriod.year: 'Year',
  StatsPeriod.allTime: 'All Time',
};

/// The Stats sub-tab (mockups 03 to 06): period chips, the listening cards,
/// rankings, Time of Day, genres, the monthly recap and Your Library.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  // The last page, shown while a new period loads so the chips stay put.
  StatsView? _last;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    if (library.value?.tracks.isEmpty ?? false) {
      return const HomeEmptyState(key: Key('stats-empty'));
    }
    final async = ref.watch(statsProvider);
    if (async.hasError && !async.hasValue) {
      return LoadError(
        title: 'Could not load Stats',
        message: async.error.toString(),
      );
    }
    final view = async.value ?? _last;
    _last = view;
    if (view == null) return const SizedBox.shrink();
    return _Page(view: view);
  }
}

class _Page extends ConsumerWidget {
  const _Page({required this.view});

  final StatsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(statsPeriodProvider);
    final listening = view.listening;
    final streak = view.streak;
    final songsPlayed = view.songsPlayed;
    final tops = view.tops;
    final mostPlayed = view.mostPlayed;
    final full = view.enoughHistory && view.historyError == null;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        2,
        16,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        if (full) ...[
          _Chips(
            selected: period,
            onSelected: ref.read(statsPeriodProvider.notifier).select,
          ),
          if (listening != null) _ListeningCard(card: listening),
          if (streak != null && songsPlayed != null)
            _Duo(streak: streak, songsPlayed: songsPlayed),
          if (tops != null) ...[
            _RankSection(
              id: 'artists',
              title: 'Top Artists',
              rows: tops.artists,
              round: true,
              seeAll: StatsList.artists,
            ),
            _RankSection(
              id: 'songs',
              title: 'Top Songs',
              rows: tops.songs,
              seeAll: StatsList.songs,
              songsSource: 'Top Songs',
            ),
            _RankSection(
              id: 'albums',
              title: 'Top Albums',
              rows: tops.albums,
              seeAll: StatsList.albums,
            ),
          ],
          if (view.timeOfDay != null) ...[
            const _Header('Time of Day'),
            _TimeOfDayCard(card: view.timeOfDay!),
          ],
          if (view.genres != null) ...[
            const _Header('Genres'),
            _GenresCard(mix: view.genres!),
          ],
          if (view.recap != null) ...[
            const SizedBox(height: 20),
            _RecapCard(recap: view.recap!),
          ],
        ] else if (view.historyError != null)
          SizedBox(
            height: 180,
            child: LoadError(
              title: 'Could not load Stats',
              message: view.historyError.toString(),
            ),
          )
        else
          const _NotEnoughCard(),
        const _Header('Your Library'),
        _LibraryGrid(overview: view.library),
        if (full && mostPlayed.isNotEmpty)
          _RankSection(
            id: 'most-played',
            title: 'Most Played of All Time',
            rows: mostPlayed,
            limit: 5,
            songsSource: 'Most Played',
            key: const Key('stats-most-played'),
          ),
      ],
    );
  }
}

// --- shared bits ----------------------------------------------------------

Color _green(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xff30d158)
    : const Color(0xff34c759);

Color _orange(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xffff9f0a)
    : const Color(0xffff9500);

const _tabular = [FontFeature.tabularFigures()];

/// A section title (`.home-h`); with [onTap] it shows a chevron and opens the
/// full list ("See All").
class _Header extends StatelessWidget {
  const _Header(this.title, {this.onTap, this.headerKey});

  final String title;
  final VoidCallback? onTap;
  final Key? headerKey;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Semantics(
      container: true,
      button: onTap != null,
      hint: onTap != null ? 'See All' : null,
      child: GestureDetector(
        key: headerKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              if (onTap != null)
                Icon(CupertinoIcons.chevron_right, size: 18, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? c.surface2 : c.surface,
        borderRadius: BorderRadius.circular(16),
        border: dark ? null : Border.all(color: c.line, width: 0.5),
      ),
      child: child,
    );
  }
}

/// "6 h 12 min" with the numbers large and the units small (`.big small`).
/// The plain text stays the formatted string.
class _BigNumber extends StatelessWidget {
  const _BigNumber(
    this.text, {
    super.key,
    required this.size,
    required this.unitSize,
    required this.color,
    this.unitColor,
    this.lineHeight,
    this.letterSpacing = 0,
  });

  final String text;
  final double size;
  final double unitSize;
  final Color color;
  final Color? unitColor;
  final double? lineHeight;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    final tokens = text.split(' ');
    final big = TextStyle(
      fontSize: size,
      height: lineHeight == null ? null : lineHeight! / size,
      fontWeight: FontWeight.w800,
      letterSpacing: letterSpacing,
      color: color,
      fontFeatures: _tabular,
    );
    final small = big.copyWith(
      fontSize: unitSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: unitColor ?? color,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < tokens.length; i++)
            TextSpan(
              text: i == 0 ? tokens[i] : ' ${tokens[i]}',
              style:
                  i == 0 ||
                      tokens[i] == '<' ||
                      tokens[i].contains(RegExp(r'[0-9]'))
                  ? big
                  : small,
            ),
        ],
      ),
    );
  }
}

// --- chips ----------------------------------------------------------------

class _Chips extends StatelessWidget {
  const _Chips({required this.selected, required this.onSelected});

  final StatsPeriod selected;
  final ValueChanged<StatsPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 14),
      child: Row(
        children: [
          for (final period in StatsPeriod.values) ...[
            if (period != StatsPeriod.week) const SizedBox(width: 8),
            Semantics(
              selected: period == selected,
              button: true,
              child: GestureDetector(
                key: Key('stats-chip-${period.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(period),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: period == selected ? c.accent : c.fill,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _chipLabels[period]!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: period == selected ? c.accentText : c.text,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --- listening time -------------------------------------------------------

class _Delta extends StatelessWidget {
  const _Delta(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final up = text.startsWith('+');
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: up ? FontWeight.w600 : FontWeight.w500,
        color: up ? _green(context) : c.muted,
      ),
    );
  }
}

const _chartHeight = 104.0;
const _labelHeight = 14.0;
const _labelGap = 6.0;
const _barArea = _chartHeight - _labelHeight - _labelGap;

class _ListeningCard extends StatelessWidget {
  const _ListeningCard({required this.card});

  final ListeningCard card;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final delta = card.delta;
    return _Card(
      key: const Key('stats-listening'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.eyebrow,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.muted,
            ),
          ),
          _BigNumber(
            card.total,
            size: 40,
            unitSize: 22,
            lineHeight: 46,
            letterSpacing: -0.8,
            color: c.text,
          ),
          if (delta != null) _Delta(delta),
          const SizedBox(height: 14),
          _BarChart(card: card),
        ],
      ),
    );
  }
}

/// The bars of the listening chart (`.week`), drawn with plain widgets.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.card});

  final ListeningCard card;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final bars = card.bars;
    final gap = bars.length <= 7
        ? 10.0
        : bars.length <= 12
        ? 8.0
        : 3.0;
    final highlighted = bars.lastIndexWhere((b) => !b.future);
    final avg = card.avgMs > 0 && card.maxMs > 0
        ? _labelHeight + _labelGap + card.avgMs / card.maxMs * _barArea
        : null;
    return SizedBox(
      height: _chartHeight,
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < bars.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: _BarColumn(
                      key: ValueKey('stats-bar-$i'),
                      bar: bars[i],
                      maxMs: card.maxMs,
                      highlighted: i == highlighted,
                      alignment: bars.length > 12 && bars[i].label != null
                          ? (i == 0
                                ? Alignment.centerLeft
                                : i == bars.length - 1
                                ? Alignment.centerRight
                                : Alignment.center)
                          : Alignment.center,
                    ),
                  ),
                ),
            ],
          ),
          if (avg != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: avg,
              child: SizedBox(
                height: 1,
                child: CustomPaint(
                  painter: _DashedLine(c.faint),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: OverflowBox(
                      maxHeight: 20,
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          card.avgLabel,
                          style: TextStyle(fontSize: 11, color: c.muted),
                        ),
                      ),
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

class _BarColumn extends StatelessWidget {
  const _BarColumn({
    super.key,
    required this.bar,
    required this.maxMs,
    required this.highlighted,
    required this.alignment,
  });

  final ChartBar bar;
  final int maxMs;
  final bool highlighted;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final empty = bar.future || bar.listenedMs <= 0 || maxMs <= 0;
    final height = empty
        ? 4.0
        : (bar.listenedMs / maxMs * _barArea).clamp(4.0, _barArea);
    final label = bar.label;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 30),
          child: Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              color: empty
                  ? c.fill
                  : highlighted
                  ? c.accent
                  : c.faint,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
                bottom: Radius.circular(3),
              ),
            ),
          ),
        ),
        const SizedBox(height: _labelGap),
        SizedBox(
          height: _labelHeight,
          width: double.infinity,
          child: label == null
              ? null
              : OverflowBox(
                  minWidth: 0,
                  maxWidth: 120,
                  alignment: alignment,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: highlighted ? c.text : c.muted,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DashedLine extends CustomPainter {
  const _DashedLine(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + 4, 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}

// --- streak and songs played ----------------------------------------------

class _Duo extends StatelessWidget {
  const _Duo({required this.streak, required this.songsPlayed});

  final StreakCard streak;
  final SongsPlayedCard songsPlayed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 12);
    final delta = songsPlayed.delta;
    final orange = _orange(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Card(
                key: const Key('stats-streak'),
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.flame_fill,
                          size: 20,
                          color: orange,
                        ),
                        const SizedBox(width: 2),
                        _BigNumber(
                          streak.label,
                          size: 28,
                          unitSize: 15,
                          lineHeight: 34,
                          color: c.text,
                          unitColor: c.muted,
                        ),
                      ],
                    ),
                    Text(
                      'Listening streak',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var i = 0; i < streak.last7.length; i++) ...[
                          if (i > 0) const SizedBox(width: 5),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: streak.last7[i] ? orange : c.fill,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Card(
                key: const Key('stats-songs-played'),
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${songsPlayed.count}',
                      style: TextStyle(
                        fontSize: 28,
                        height: 34 / 28,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                        fontFeatures: _tabular,
                      ),
                    ),
                    Text(
                      'Songs played',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                    if (delta != null) ...[
                      const SizedBox(height: 6),
                      _Delta(delta),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- rankings ---------------------------------------------------------------

class _RankSection extends ConsumerWidget {
  const _RankSection({
    super.key,
    required this.id,
    required this.title,
    required this.rows,
    this.round = false,
    this.seeAll,
    this.songsSource = '',
    this.limit = 3,
  });

  final String id;
  final String title;
  final List<RankRow> rows;
  final bool round;
  final StatsList? seeAll;

  /// The queue source label when a song row is tapped.
  final String songsSource;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final list = seeAll;
    return Column(
      key: list != null ? Key('stats-top-$id') : null,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title,
          onTap: list == null ? null : () => openStatsList(context, list),
          headerKey: list != null ? Key('stats-see-all-$id') : null,
        ),
        for (var i = 0; i < rows.length && i < limit; i++)
          RankRowTile(
            key: Key('stats-$id-$i'),
            rank: i + 1,
            row: rows[i],
            round: round,
            onTap: () => tapRankRow(
              context,
              ref,
              rows,
              i,
              songsSource: songsSource,
              backLabel: homeBackLabel,
            ),
          ),
      ],
    );
  }
}

// --- time of day ------------------------------------------------------------

const _partNames = ['Morning', 'Afternoon', 'Evening', 'Night'];

// The hours of Morning, Afternoon, Evening and Night.
const _partHours = [(5, 11), (12, 17), (18, 23), (0, 4)];

class _TimeOfDayCard extends StatelessWidget {
  const _TimeOfDayCard({required this.card});

  final TimeOfDayCard card;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final (from, to) = _partHours[card.highlighted];
    final axis = TextStyle(
      fontSize: 11,
      color: c.muted,
      fontFeatures: _tabular,
    );
    return _Card(
      key: const Key('stats-time-of-day'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.eyebrow,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 84,
            width: double.infinity,
            child: CustomPaint(
              painter: _HourBars(
                hourly: card.hourly,
                color: c.faint,
                highlight: c.accent,
                from: from,
                to: to,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in ['12 AM', '6 AM', '12 PM', '6 PM', '12 AM'])
                Text(label, style: axis),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line, width: 0.5)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${card.partsPercent[i]}%',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: i == card.highlighted ? c.accent : c.text,
                            fontFeatures: _tabular,
                          ),
                        ),
                        Text(
                          _partNames[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 24 rounded bars; the hours [from]..[to] (wrapping is not needed: Night is
/// 0..4) use the highlight color.
class _HourBars extends CustomPainter {
  const _HourBars({
    required this.hourly,
    required this.color,
    required this.highlight,
    required this.from,
    required this.to,
  });

  final List<int> hourly;
  final Color color;
  final Color highlight;
  final int from;
  final int to;

  @override
  void paint(Canvas canvas, Size size) {
    final max = hourly.fold<int>(0, (a, b) => b > a ? b : a);
    if (max <= 0) return;
    final slot = size.width / 24;
    final width = slot * 0.75;
    for (var h = 0; h < 24; h++) {
      final height = (hourly[h] / max * (size.height - 4)).clamp(2.0, 80.0);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(h * slot, size.height - height, width, height),
        const Radius.circular(2.5),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = h >= from && h <= to ? highlight : color,
      );
    }
  }

  @override
  bool shouldRepaint(_HourBars old) =>
      old.hourly != hourly ||
      old.color != color ||
      old.highlight != highlight ||
      old.from != from ||
      old.to != to;
}

// --- genres -------------------------------------------------------------------

class _GenresCard extends StatelessWidget {
  const _GenresCard({required this.mix});

  final GenreMix mix;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    // The accent fading into the background; "Other" (the fifth) is grey.
    Color shade(int i) => i >= 4
        ? c.faint
        : Color.lerp(c.bg, c.accent, const [1.0, 0.72, 0.48, 0.30][i])!;
    final genres = mix.genres;
    return _Card(
      key: const Key('stats-genres'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mix.eyebrow,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (var i = 0; i < genres.length; i++)
                    if (genres[i].percent > 0) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: genres[i].percent,
                        child: ColoredBox(
                          color: shade(i),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < genres.length; i++)
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: shade(i),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      genres[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: c.text),
                    ),
                  ),
                  Text(
                    '${genres[i].percent}%',
                    style: TextStyle(
                      fontSize: 15,
                      color: c.muted,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// --- monthly recap ------------------------------------------------------------

class _RecapCard extends ConsumerWidget {
  const _RecapCard({required this.recap});

  final MonthRecap recap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color white(double alpha) => Colors.white.withValues(alpha: alpha);
    final top = recap.topSong;
    final topTrack = top == null
        ? null
        : (top.target is SongTarget ? (top.target as SongTarget).track : null);
    final cover = topTrack?.coverFile;

    Widget fact({
      required Widget lead,
      required String title,
      required String sub,
    }) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: white(0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            lead,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: white(0.75)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      key: const Key('stats-recap'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.78],
          colors: dark
              ? [
                  Color.lerp(Colors.black, c.accent, 0.62)!,
                  const Color(0xff17121f),
                ]
              : const [Color(0xff2b2b31), Color(0xff16161a)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            width: 170,
            height: 170,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [white(0.22), white(0)],
                  stops: const [0, 0.68],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(CupertinoIcons.sparkles, size: 14, color: white(0.75)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        recap.eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: white(0.75),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _BigNumber(
                  recap.total,
                  size: 40,
                  unitSize: 22,
                  lineHeight: 46,
                  letterSpacing: -0.8,
                  color: Colors.white,
                ),
                Text(
                  recap.caption,
                  style: TextStyle(fontSize: 14, color: white(0.8)),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (top != null) ...[
                      fact(
                        lead: Artwork(
                          file: cover == null
                              ? null
                              : ref.watch(storageProvider).coverFile(cover),
                          size: 40,
                          radius: 6,
                        ),
                        title: top.title,
                        sub: 'Top song · ${top.playsLabel}',
                      ),
                      const SizedBox(width: 10),
                    ],
                    fact(
                      lead: Text(
                        '${recap.newFinds}',
                        style: const TextStyle(
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFeatures: _tabular,
                        ),
                      ),
                      title: 'New finds',
                      sub: 'songs played the first time',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- your library -------------------------------------------------------------

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({required this.overview});

  final LibraryOverview overview;

  @override
  Widget build(BuildContext context) {
    final cells = [
      ('Songs', '${overview.songs}'),
      ('Albums', '${overview.albums}'),
      ('Artists', '${overview.artists}'),
      ('Playlists', '${overview.playlists}'),
      ('Total duration', overview.duration),
      ('Storage used', overview.storage ?? '…'),
    ];
    return Column(
      key: const Key('stats-library'),
      children: [
        for (var row = 0; row < cells.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _LibraryCell(cells[row].$1, cells[row].$2)),
                const SizedBox(width: 10),
                Expanded(
                  child: _LibraryCell(cells[row + 1].$1, cells[row + 1].$2),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LibraryCell extends StatelessWidget {
  const _LibraryCell(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return _Card(
      key: Key('stats-library-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BigNumber(
            value,
            key: Key('stats-library-n-$label'),
            size: 24,
            unitSize: 15,
            lineHeight: 30,
            color: c.text,
            unitColor: c.muted,
          ),
          Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
        ],
      ),
    );
  }
}

// --- not enough history ---------------------------------------------------------

class _NotEnoughCard extends StatelessWidget {
  const _NotEnoughCard();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return _Card(
      key: const Key('stats-not-enough'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.fill),
            child: Icon(CupertinoIcons.chart_bar, size: 24, color: c.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stats fill up as you listen',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Play a few songs and your listening time, streak, top '
                  'artists and favorite hours show up here.',
                  style: TextStyle(fontSize: 14, height: 1.35, color: c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
