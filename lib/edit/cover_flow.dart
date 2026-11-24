import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/edit/cover_block.dart';
import 'package:owntune/edit/cover_crop_screen.dart';
import 'package:owntune/edit/cover_image.dart';
import 'package:owntune/edit/cover_picker.dart';
import 'package:owntune/library/songs_screen.dart' show DialogAction;

// Top-level so the isolate closures capture only their arguments (a closure
// inside a State would try to send the whole widget tree).
Future<UprightCover?> _uprightInIsolate(Uint8List bytes) =>
    Isolate.run(() => uprightCover(bytes));

Future<Uint8List> _cropInIsolate(Uint8List bytes, Rect rect) =>
    Isolate.run(() => cropCover(bytes, rect));

/// The shared cover flow of Edit Info and the playlist screens: pick an image
/// as [action] says (photos or file), straighten it in an isolate, let the
/// user crop it square, and crop it in an isolate. Gives the JPEG, or null
/// when cancelled, when [action] is not a pick, or after an error, which is
/// shown in a dialog (no logs on the iPhone).
///
/// [onBusy] is called with true while a picked image is being decoded or
/// cropped (can take seconds for a big photo) and with false afterwards; it
/// may be called while [context] is gone, so the caller checks `mounted`.
Future<Uint8List?> pickAndCropCover(
  BuildContext context,
  CoverPicker picker,
  CoverAction action, {
  required void Function(bool busy) onBusy,
}) async {
  final Uint8List? bytes;
  try {
    bytes = switch (action) {
      CoverAction.photos => await picker.pickPhoto(),
      CoverAction.file => await picker.pickFile(),
      CoverAction.remove => null,
    };
  } on Object catch (e) {
    if (context.mounted) await _showCoverError(context, '$e');
    return null;
  }
  if (bytes == null || !context.mounted) return null;

  /// Runs [work] with the spinner on; any error is shown and gives null.
  Future<({T value})?> process<T>(Future<T> Function() work) async {
    onBusy(true);
    try {
      return (value: await work());
    } on Object catch (e) {
      if (context.mounted) await _showCoverError(context, '$e');
      return null;
    } finally {
      onBusy(false);
    }
  }

  final Uint8List source = bytes;
  final upright = await process(() => _uprightInIsolate(source));
  if (!context.mounted || upright == null) return null;
  final image = upright.value;
  if (image == null) {
    await _showCoverError(
      context,
      "This image can't be read. Choose a JPEG or PNG.",
    );
    return null;
  }
  final rect = await openCoverCrop(context, image);
  if (rect == null || !context.mounted) return null;
  final data = await process(() => _cropInIsolate(image.bytes, rect));
  if (!context.mounted || data == null) return null;
  return data.value;
}

Future<void> _showCoverError(BuildContext context, String message) =>
    showAdaptiveDialog<void>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text("Couldn't use this image"),
        content: SelectableText(message),
        actions: [
          DialogAction(label: 'OK', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
