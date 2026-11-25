import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/buttons.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/text_tabs.dart';
import 'package:owntune/app/theme.dart';
import 'package:owntune/data/sources/online_link.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/download/download_job.dart';
import 'package:owntune/download/download_sheet.dart';
import 'package:owntune/download/downloads_button.dart';
import 'package:owntune/download/online_image.dart';
import 'package:owntune/library/navigation.dart';
import 'package:owntune/library/search_screen.dart';
import 'package:owntune/player/mini_player.dart';

/// Opens Search Online above the tab shell.
Future<void> openSearchOnline(
  BuildContext context, {
  required String backLabel,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => SearchOnlineScreen(backLabel: backLabel),
  ),
);

/// Search YouTube Music (songs), YouTube (videos) or SoundCloud and pick a
/// result to download (mockups 06, 07, 08).
class SearchOnlineScreen extends ConsumerStatefulWidget {
  const SearchOnlineScreen({super.key, this.backLabel = 'Library'});

  final String backLabel;

  @override
  ConsumerState<SearchOnlineScreen> createState() => _SearchOnlineScreenState();
}

class _SearchOnlineScreenState extends ConsumerState<SearchOnlineScreen> {
  final _query = TextEditingController();
  late OnlineSourceId _source = ref.read(settingsProvider).onlineSource;

  /// The query the shown results (or error) belong to; null shows the
  /// recent searches.
  String? _searched;
  List<OnlineResult>? _results;
  String? _error;
  var _loading = false;
  var _serial = 0;

  /// Whether the spinner belongs to a link lookup, which an edit of the field
  /// cancels.
  var _linkLoading = false;

  /// The trimmed text of the link whose lookup and sheet are in progress.
  String? _openingLink;

  /// False for the error of a link: there is no search to repeat.
  var _retryable = true;

  /// The field's text at the last change, to tell a paste from typing.
  var _lastText = '';

  /// Whether the field holds a link whose lookup, sheet or error the body
  /// shows. The next edit ends it and brings back what was shown before.
  var _linkActive = false;

  /// The query the shown results belonged to before the link; [_searched]
  /// is null while the field holds a link.
  String? _searchedBeforeLink;

  @override
  void initState() {
    super.initState();
    _query.addListener(_queryChanged);
  }

  void _queryChanged() {
    final text = _query.text;
    final last = _lastText;
    _lastText = text;
    if (text == last) return;
    if (_linkLoading) {
      // The user moved on: the late answer must not open a sheet, and the
      // same link can be submitted again.
      setState(() {
        _serial++;
        _loading = false;
        _linkLoading = false;
        _openingLink = null;
      });
    }
    if (_linkActive) {
      // Back to what the body showed before the link: the previous results
      // (kept in `_results`) or the recent searches.
      setState(() {
        _linkActive = false;
        _searched = _searchedBeforeLink;
        _searchedBeforeLink = null;
        if (!_retryable) {
          _error = null;
          _retryable = true;
        }
      });
    }
    if (text.isEmpty) {
      setState(() {
        _serial++;
        _searched = null;
        _results = null;
        _error = null;
        _retryable = true;
        _loading = false;
      });
    }
    // A paste (or a typed-in recent search) arrives in one piece; typing and
    // deleting change the text by one character.
    if (_insertedLength(last, text) > 1) {
      final link = parseOnlineLink(text);
      if (link != null) _openLink(link);
    }
  }

  /// How many characters the change from [before] to [after] inserted,
  /// found through their common prefix and suffix; a paste over a selection
  /// counts as its inserted text.
  static int _insertedLength(String before, String after) {
    final shorter = math.min(before.length, after.length);
    var prefix = 0;
    while (prefix < shorter &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shorter - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }
    return after.length - prefix - suffix;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final q = text.trim();
    if (q.isEmpty) return;
    if (parseOnlineLink(q) case final link?) {
      // A paste already started this lookup; submitting must not repeat it.
      if (_openingLink != q) _openLink(link);
      return;
    }
    ref.read(settingsProvider.notifier).addRecentSearch(q);
    _search(q);
  }

  Future<void> _search(String q) async {
    final serial = ++_serial;
    setState(() {
      _searched = q;
      _linkActive = false;
      _loading = true;
      _linkLoading = false;
      _results = null;
      _error = null;
      _retryable = true;
    });
    final source = ref.read(onlineSourcesProvider)[_source]!;
    try {
      final results = await source.search(q);
      if (!mounted || serial != _serial) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || serial != _serial) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Looks up the song of a pasted link and opens its Download sheet, on any
  /// tab. The shown results stay behind the spinner and come back after it.
  Future<void> _openLink(OnlineLink link) async {
    final serial = ++_serial;
    final text = _query.text.trim();
    _openingLink = text;
    if (!_linkActive) {
      // While the field holds a link there is no query to repeat; a search
      // still running is dropped by the serial.
      _linkActive = true;
      _searchedBeforeLink = _searched;
      _searched = null;
    }
    try {
      await _lookUpAndOpen(link, serial);
    } finally {
      if (_openingLink == text) _openingLink = null;
    }
  }

  Future<void> _lookUpAndOpen(OnlineLink link, int serial) async {
    if (link case UnsupportedLink(:final message)) {
      setState(() {
        _loading = false;
        _linkLoading = false;
        _error = message;
        _retryable = false;
      });
      return;
    }
    final id = link is YoutubeLink
        ? OnlineSourceId.youtube
        : OnlineSourceId.soundcloud;
    setState(() {
      _loading = true;
      _linkLoading = true;
      if (!_retryable) {
        _error = null;
        _retryable = true;
      }
    });
    final OnlineResult result;
    try {
      result = await ref.read(onlineSourcesProvider)[id]!.lookup(link);
    } on Object catch (e) {
      if (!mounted || serial != _serial) return;
      setState(() {
        _error = '$e';
        _retryable = false;
        _loading = false;
        _linkLoading = false;
      });
      return;
    }
    if (!mounted || serial != _serial) return;
    setState(() {
      _loading = false;
      _linkLoading = false;
    });
    await showDownloadSheet(context, result);
  }

  void _switchTo(OnlineSourceId source) {
    if (source == _source) return;
    setState(() {
      _source = source;
      // Results kept behind a link belong to the other tab.
      if (_linkActive) {
        _results = null;
        _searchedBeforeLink = null;
      }
    });
    final notifier = ref.read(settingsProvider.notifier);
    notifier.set(ref.read(settingsProvider).copyWith(onlineSource: source));
    final searched = _searched;
    if (searched != null) _search(searched);
  }

  void _searchRecent(String q) {
    _query.text = q;
    _submit(q);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    return Scaffold(
      backgroundColor: c.bg,
      bottomNavigationBar: const MiniPlayer(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              NavRow(
                backLabel: widget.backLabel,
                trailing: const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: DownloadsButton(round: false),
                ),
              ),
              IgnorePointer(
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 44,
                    child: Center(
                      child: Text(
                        'Search Online',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextTabs<OnlineSourceId>(
              segments: const {
                OnlineSourceId.ytmusic: 'Songs',
                OnlineSourceId.youtube: 'Videos',
                OnlineSourceId.soundcloud: 'SoundCloud',
              },
              value: _source,
              onChanged: _switchTo,
            ),
          ),
          TabSearchField(
            key: const Key('online-search-field'),
            label: switch (_source) {
              OnlineSourceId.ytmusic => 'Search Songs',
              OnlineSourceId.youtube => 'Search Videos',
              OnlineSourceId.soundcloud => 'Search SoundCloud',
            },
            controller: _query,
            onSubmitted: _submit,
          ),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _body(OwntuneColors c) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: CircularProgressIndicator.adaptive(key: Key('online-loading')),
        ),
      );
    }
    if (_error case final error?) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
        child: Column(
          children: [
            SelectableText(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: c.muted),
            ),
            if (_retryable && _searched != null) ...[
              const SizedBox(height: 16),
              PillButton(
                label: 'Retry',
                secondary: true,
                onPressed: () => _search(_searched!),
              ),
            ],
          ],
        ),
      );
    }
    final results = _results;
    if (results != null) {
      if (results.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(
            'No results',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: c.muted),
          ),
        );
      }
      return ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: results.length,
        itemBuilder: (context, i) => _ResultRow(result: results[i]),
      );
    }
    return _RecentSearches(onSearch: _searchRecent);
  }
}

/// The last queries below the empty search field; swipe one away.
class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({required this.onSearch});

  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final recent = ref.watch(settingsProvider).recentSearches;
    if (recent.isEmpty) return const SizedBox.shrink();
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Text(
            'Recent',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
        ),
        for (final q in recent)
          Dismissible(
            key: ValueKey('recent-$q'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) =>
                ref.read(settingsProvider.notifier).removeRecentSearch(q),
            background: Container(
              color: const Color(0xffff3b30),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(CupertinoIcons.delete, color: Colors.white),
            ),
            child: InkWell(
              onTap: () => onSearch(q),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.clock, size: 18, color: c.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        q,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 17, color: c.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One result: square cover (songs) or 16:9 thumbnail (videos), title,
/// subtitle and its library/download state.
class _ResultRow extends ConsumerWidget {
  const _ResultRow({required this.result});

  final OnlineResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<OwntuneColors>()!;
    final r = result;
    final inLibrary = ref.watch(
      librarySourceKeysProvider.select((keys) => keys.contains(r.sourceKey)),
    );
    // Only this result's job: progress of other downloads does not rebuild
    // the row.
    final job = ref.watch(
      downloadControllerProvider.select(
        (jobs) => jobs
            .where((j) => j.isActive && j.result.sourceKey == r.sourceKey)
            .firstOrNull,
      ),
    );
    final video = r.source == OnlineSourceId.youtube;
    final soundcloud = r.source == OnlineSourceId.soundcloud;
    final duration = r.duration == null ? null : formatDuration(r.duration!);
    final available = r.availability == OnlineAvailability.available;
    final image = video
        ? Stack(
            children: [
              OnlineImage(url: r.thumbnail, width: 112, height: 63, radius: 6),
              if (duration != null) _DurationBadge(duration),
            ],
          )
        : soundcloud
        ? Stack(
            children: [
              OnlineImage(url: r.thumbnail, width: 48, height: 48),
              if (duration != null) _DurationBadge(duration, compact: true),
            ],
          )
        : OnlineImage(url: r.thumbnail, width: 48, height: 48);
    final state = available
        ? _state(inLibrary, job)
        : (_unavailableIcon(r.availability), r.availability.note!);
    final dim = available ? 1.0 : 0.45;
    return InkWell(
      key: ValueKey('online-row-${r.sourceKey}'),
      onTap: available ? () => showDownloadSheet(context, r) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          crossAxisAlignment: video
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Opacity(opacity: dim, child: image),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Opacity(
                    opacity: dim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.title,
                          maxLines: video || soundcloud ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: video || soundcloud ? 15 : 17,
                            height: 1.25,
                            color: c.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (r.subtitle.isNotEmpty) r.subtitle,
                            if (!video && !soundcloud && duration != null)
                              duration,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  if (state != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          state.$1,
                          size: 13,
                          color: inLibrary || !available ? c.muted : c.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          state.$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: inLibrary || !available ? c.muted : c.accent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _unavailableIcon(OnlineAvailability a) => switch (a) {
    OnlineAvailability.protected => CupertinoIcons.lock,
    OnlineAvailability.previewOnly => CupertinoIcons.time,
    _ => CupertinoIcons.nosign,
  };

  static (IconData, String)? _state(bool inLibrary, DownloadJob? job) {
    if (job != null) {
      return switch (job.phase) {
        DownloadPhase.downloading when job.total > 0 => (
          CupertinoIcons.arrow_down_circle,
          'Downloading ${job.received * 100 ~/ job.total} %',
        ),
        DownloadPhase.importing => (
          CupertinoIcons.arrow_down_circle,
          'Adding to library…',
        ),
        DownloadPhase.downloading => (
          CupertinoIcons.arrow_down_circle,
          'Downloading',
        ),
        _ => (CupertinoIcons.clock, 'Waiting'),
      };
    }
    if (inLibrary) return (CupertinoIcons.checkmark, 'In Library');
    return null;
  }
}

/// The duration on the bottom right of a thumbnail or cover.
class _DurationBadge extends StatelessWidget {
  const _DurationBadge(this.text, {this.compact = false});

  final String text;

  /// Smaller and tighter, for the 48 px square art.
  final bool compact;

  @override
  Widget build(BuildContext context) => Positioned(
    right: compact ? 2 : 4,
    bottom: compact ? 2 : 4,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(0, 0, 0, 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 9 : 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    ),
  );
}

/// `3:08`, `1:02:14`.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
