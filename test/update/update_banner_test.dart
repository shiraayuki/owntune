import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/update/app_version.dart';
import 'package:owntune/update/update_controller.dart';

import '../support/fakes.dart';

const offered = UpdateInfo(
  current: AppVersion(0, 10, 0),
  latest: AppVersion(0, 11, 0),
  enabled: true,
);

void main() {
  late FakeUpdateController controller;
  late FakeUpdateLauncher launcher;

  Future<void> pump(WidgetTester t, UpdateInfo info) async {
    controller = FakeUpdateController(info);
    launcher = FakeUpdateLauncher();
    await pumpApp(
      t,
      updateLauncher: launcher,
      overrides: [updateControllerProvider.overrideWith(() => controller)],
    );
  }

  testWidgets('Home shows an available update on both sub-tabs', (t) async {
    await pump(t, offered);
    expect(find.text('owntune 0.11.0 is available'), findsOneWidget);
    await t.tap(find.text('Stats'));
    await t.pumpAndSettle();
    expect(find.text('owntune 0.11.0 is available'), findsOneWidget);
  });

  testWidgets('Update opens the update target', (t) async {
    await pump(t, offered);
    await t.tap(find.text('Update'));
    await t.pump();
    expect(launcher.opened, 1);
  });

  testWidgets('Dismiss hides the banner', (t) async {
    await pump(t, offered);
    await t.tap(find.byTooltip('Dismiss'));
    await t.pumpAndSettle();
    expect(controller.dismissCalls, 1);
    expect(find.byKey(const Key('update-banner')), findsNothing);
  });

  testWidgets('no banner without an update', (t) async {
    await pump(
      t,
      const UpdateInfo(
        current: AppVersion(0, 11, 0),
        latest: AppVersion(0, 11, 0),
        enabled: true,
      ),
    );
    expect(find.byKey(const Key('update-banner')), findsNothing);
  });

  testWidgets('no banner for a dismissed version', (t) async {
    await pump(
      t,
      const UpdateInfo(
        current: AppVersion(0, 10, 0),
        latest: AppVersion(0, 11, 0),
        dismissed: AppVersion(0, 11, 0),
        enabled: true,
      ),
    );
    expect(find.byKey(const Key('update-banner')), findsNothing);
  });
}
