import 'package:file_picker/file_picker.dart';

/// The system document picker, behind an interface so tests can fake it.
class AudioFilePicker {
  const AudioFilePicker();

  /// Lets the user pick any number of files and returns their local paths;
  /// empty when cancelled. Any file type can be picked, so unsupported files
  /// (e.g. `.ogg`) reach the importer and are reported in the summary.
  Future<List<String>> pick() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Import Music',
      type: FileType.any,
    );
    return [for (final f in files) ?f.path];
  }

  /// Removes the copies the picker made (iOS and Android pick into a
  /// temporary folder); a no-op where the picker returns the originals.
  Future<void> clearTemporaryFiles() => FilePicker.clearTemporaryFiles();
}
