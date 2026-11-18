import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/core_status.dart';

class OwntuneApp extends StatelessWidget {
  const OwntuneApp({super.key, required this.status});

  final CoreStatus status;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'owntune',
      theme: ThemeData(useMaterial3: true),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: HomeScreen(status: status),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.status});

  final CoreStatus status;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          // Scrollbar, damit lange Fehlermeldungen auf dem iPhone lesbar bleiben.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('owntune', style: text.headlineMedium),
                const SizedBox(height: 16),
                ...switch (status) {
                  CoreReady(:final formats) => [
                    Text('Rust-Kern: OK', style: text.titleMedium),
                    const SizedBox(height: 8),
                    Text(formats.join(', ')),
                  ],
                  CoreFailed(:final message) => [
                    Text('Rust-Kern: Fehler', style: text.titleMedium),
                    const SizedBox(height: 8),
                    SelectableText(message, textAlign: TextAlign.center),
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}
