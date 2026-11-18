import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/core_status.dart';
import 'package:owntune/app/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = await loadCoreStatus();
  runApp(OwntuneApp(status: status));
}
