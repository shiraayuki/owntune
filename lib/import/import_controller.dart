import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/import/importer.dart';

/// What the import UI shows.
sealed class ImportState {
  const ImportState();
}

final class ImportIdle extends ImportState {
  const ImportIdle();
}

final class ImportRunning extends ImportState {
  const ImportRunning(this.progress, this.hidden);

  final ImportProgress progress;

  /// The user hid the progress sheet; the import keeps running.
  final bool hidden;
}

final class ImportDone extends ImportState {
  const ImportDone(this.summary);

  final ImportSummary summary;
}

/// The import itself failed (not a single file, those end up in the
/// summary). Shown on screen, since the iPhone gives us no logs.
final class ImportFailed extends ImportState {
  const ImportFailed(this.message);

  final String message;
}

/// Runs Import Music, one at a time, through the single [Importer]
/// instance, and holds what the import sheets show.
class ImportController extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportIdle();

  bool get _running => state is ImportRunning;

  /// Opens the picker and imports what was picked. Does nothing while an
  /// import runs or when the picker returns no files.
  Future<void> pickAndImport() async {
    if (_running) return;
    final picker = ref.read(filePickerProvider);
    final List<String> paths;
    try {
      paths = await picker.pick();
    } on Object catch (e) {
      if (ref.mounted && !_running) {
        state = ImportFailed('Could not open the file picker: $e');
      }
      return;
    }
    if (!ref.mounted || paths.isEmpty || _running) return;
    await start(paths);
    try {
      await picker.clearTemporaryFiles();
    } on Object {
      // Only temporary copies are left behind; the OS cleans them up.
    }
  }

  /// Imports [paths]. Ignored while another Import Music runs or for no
  /// paths, so the sheets show one import at a time. (The [Importer] itself
  /// queues calls, e.g. from downloads.)
  Future<void> start(List<String> paths) async {
    if (_running || paths.isEmpty) return;
    state = ImportRunning(
      ImportProgress(done: 0, total: paths.length, currentName: ''),
      false,
    );
    try {
      final summary = await ref
          .read(importerProvider)
          .importFiles(
            paths,
            onProgress: (p) {
              if (!ref.mounted) return;
              if (state case ImportRunning(:final hidden)) {
                state = ImportRunning(p, hidden);
              }
            },
          );
      if (ref.mounted) state = ImportDone(summary);
    } on Object catch (e) {
      if (ref.mounted) state = ImportFailed(e.toString());
    }
  }

  /// Hides the progress sheet; the import keeps running.
  void hide() {
    if (state case ImportRunning(:final progress)) {
      state = ImportRunning(progress, true);
    }
  }

  /// Closes the summary (or failure) sheet.
  void dismiss() {
    if (state is ImportDone || state is ImportFailed) {
      state = const ImportIdle();
    }
  }
}
