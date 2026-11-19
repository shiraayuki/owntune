import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/app/startup.dart';
import 'package:owntune/app/startup_error_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  switch (await startUp()) {
    case StartupReady(
      :final db,
      :final storage,
      :final settings,
      :final player,
    ):
      runApp(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            storageProvider.overrideWithValue(storage),
            initialSettingsProvider.overrideWithValue(settings),
            initialPlayerSnapshotProvider.overrideWithValue(player),
          ],
          child: const OwntuneApp(),
        ),
      );
    case StartupFailed(:final message):
      runApp(StartupErrorApp(message: message));
  }
}
