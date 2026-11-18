import 'package:owntune/src/rust/api/metadata.dart';
import 'package:owntune/src/rust/frb_generated.dart';

/// Ergebnis des Starts des Rust-Kerns.
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

/// Lädt den Rust-Kern und fragt die unterstützten Formate ab.
///
/// Wirft nie: Jeder Fehler wird als [CoreFailed] zurückgegeben, damit die App
/// ihn anzeigen kann. Auf dem iPhone gibt es ohne Mac keine andere Diagnose.
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
