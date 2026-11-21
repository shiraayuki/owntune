import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';

/// Multi-select in Songs: null while off, else the selected track ids.
/// Ids of songs that leave the library (deleted elsewhere, an import
/// rolled back) drop out of the selection.
class SongSelection extends Notifier<Set<int>?> {
  @override
  Set<int>? build() {
    ref.listen(tracksProvider, (_, next) {
      final selected = state;
      final tracks = next.value;
      if (selected == null || tracks == null) return;
      final ids = {for (final t in tracks) t.id};
      final kept = selected.intersection(ids);
      if (kept.length != selected.length) state = kept;
    });
    return null;
  }

  /// Turns selection mode on with nothing selected.
  void start() => state = const {};

  /// Selects or unselects [id]; does nothing while selection mode is off.
  void toggle(int id) {
    final selected = state;
    if (selected == null) return;
    state = selected.contains(id)
        ? ({...selected}..remove(id))
        : {...selected, id};
  }

  /// Turns selection mode off.
  void end() => state = null;
}
