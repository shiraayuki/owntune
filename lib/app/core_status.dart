import 'package:owntune/src/rust/api/metadata.dart';
import 'package:owntune/src/rust/frb_generated.dart';

/// Result of starting the Rust core.
sealed class CoreStatus {
  const CoreStatus();
}

final class CoreReady extends CoreStatus {
  const CoreReady(this.formats);

  final List<String> formats;
}

final class CoreFailed extends CoreStatus {
  const CoreFailed(this.message);

  final String message;
}

/// Loads the Rust core and queries the supported formats.
///
/// Never throws: every error is returned as [CoreFailed] so the app can show
/// it. Without a Mac there is no other way to diagnose failures on the iPhone.
Future<CoreStatus> loadCoreStatus({
  Future<void> Function()? init,
  List<String> Function()? formats,
}) async {
  try {
    await (init ?? RustLib.init)();
    return CoreReady((formats ?? supportedFormats)());
  } on Object catch (e) {
    return CoreFailed(e.toString());
  }
}
