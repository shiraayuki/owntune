import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Picks a cover image, behind an interface so tests can fake it.
class CoverPicker {
  const CoverPicker();

  /// The photo library (iOS/Android; a file dialog elsewhere). On iOS the
  /// picker hands over a compatible representation, so HEIC photos arrive
  /// as JPEG. Null when cancelled.
  Future<Uint8List?> pickPhoto() => _pick(
    type: FileType.image,
    darwinOptions: const DarwinOptions(
      assetRepresentationMode: DarwinAssetRepresentationMode.compatible,
    ),
  );

  /// The Files app / file dialog, limited to image files. HEIC can be
  /// picked but not read; the caller reports that. Null when cancelled.
  Future<Uint8List?> pickFile() => _pick(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
  );

  Future<Uint8List?> _pick({
    required FileType type,
    List<String>? allowedExtensions,
    DarwinOptions darwinOptions = const DarwinOptions(),
  }) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose Cover',
      type: type,
      allowedExtensions: allowedExtensions,
      darwinOptions: darwinOptions,
    );
    final path = files.firstOrNull?.path;
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } finally {
      try {
        await FilePicker.clearTemporaryFiles();
      } on Object {
        // Best effort; the system clears its temp folder too.
      }
    }
  }
}
