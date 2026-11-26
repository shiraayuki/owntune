import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoSwitch;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:owntune/app/app_shell.dart';
import 'package:owntune/app/providers.dart';
import 'package:owntune/settings/settings.dart';
import 'package:owntune/settings/settings_sheet.dart';

import '../support/fakes.dart';

void main() {
  group('formatBytes', () {
    test('below 1 GB: whole MB, 1024-based', () {
      expect(formatBytes(431000000), '411 MB');
      expect(formatBytes(0), '0 MB');
    });

    test('from 1 GB: one decimal', () {
      expect(formatBytes(1 << 30), '1.0 GB');
      expect(formatBytes((1.2 * (1 << 30)).round()), '1.2 GB');
    });
  });

  late FakeSettingsRepository settingsRepo;

  Future<void> openSettings(
    WidgetTester t, {
    int songs = 47,
    int bytes = 431000000,
  }) async {
    settingsRepo = FakeSettingsRepository();
    await pumpApp(
      t,
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        trackRepositoryProvider.overrideWithValue(
          FakeTrackRepository(songCount: songs, bytes: bytes),
        ),
        appVersionProvider.overrideWith((ref) async => '9.8.7'),
      ],
    );
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
  }

  AppSettings current(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(AppShell)))
          .read(settingsProvider);

  testWidgets('the menu entry opens the settings sheet', (t) async {
    await openSettings(t);
    expect(find.byType(SettingsSheet), findsOneWidget);
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('ACCENT COLOR · DARK MODE'), findsOneWidget);
    expect(find.text('Light mode stays monochrome.'), findsOneWidget);
  });

  testWidgets('Playback has Normalize Volume, on by default', (t) async {
    await openSettings(t);
    expect(find.text('PLAYBACK'), findsOneWidget);
    expect(find.text('Normalize Volume'), findsOneWidget);
    expect(find.text('Plays all songs at a similar loudness.'), findsOneWidget);
    final toggle = t.widget<CupertinoSwitch>(
      find.byKey(const Key('normalize-volume')),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('tapping Normalize Volume turns it off and saves it', (t) async {
    await openSettings(t);
    await t.ensureVisible(find.byKey(const Key('normalize-volume')));
    await t.tap(find.byKey(const Key('normalize-volume')));
    await t.pumpAndSettle();

    expect(current(t).normalizeVolume, isFalse);
    expect(settingsRepo.saved.last.normalizeVolume, isFalse);
    final toggle = t.widget<CupertinoSwitch>(
      find.byKey(const Key('normalize-volume')),
    );
    expect(toggle.value, isFalse);
  });

  testWidgets('Done closes the sheet', (t) async {
    await openSettings(t);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsNothing);
  });

  testWidgets('selecting Light applies and persists it', (t) async {
    await openSettings(t);
    await t.tap(find.text('Light'));
    await t.pumpAndSettle();

    expect(current(t).mode, AppearanceMode.light);
    expect(settingsRepo.saved.last.mode, AppearanceMode.light);
    final app = t.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
  });

  testWidgets('tapping the Blue swatch sets accent Blue', (t) async {
    await openSettings(t);
    await t.tap(find.bySemanticsLabel('Blue'));
    await t.pumpAndSettle();

    expect(current(t).accent, const Color(0xff4d8dff));
    expect(settingsRepo.saved.last.accent, const Color(0xff4d8dff));
  });

  testWidgets('appearance and accent changes within one frame both stick', (
    t,
  ) async {
    await openSettings(t);
    await t.tap(find.text('Dark'));
    await t.tap(find.bySemanticsLabel('Blue'));
    await t.pumpAndSettle();

    const expected = AppSettings(
      mode: AppearanceMode.dark,
      accent: Color(0xff4d8dff),
    );
    expect(current(t), expected);
    expect(settingsRepo.saved.last, expected);
  });

  testWidgets('the selected swatch is marked selected', (t) async {
    await openSettings(t);
    expect(
      t.getSemantics(find.bySemanticsLabel('Coral')),
      isSemantics(isSelected: true, isButton: true, hasTapAction: true),
    );
    expect(
      t.getSemantics(find.bySemanticsLabel('Blue')),
      isSemantics(isSelected: false),
    );
  });

  testWidgets('the sheet fits a 360pt wide Android phone', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await openSettings(t);
    // A RenderFlex overflow would fail the test on its own.
    expect(find.bySemanticsLabel('Pink'), findsOneWidget);
    expect(
      t.getBottomRight(find.bySemanticsLabel('Pink')).dx,
      lessThanOrEqualTo(360 - 16 - 12 + 0.01),
    );
  });

  testWidgets('swatches are at least 44pt tap targets', (t) async {
    await openSettings(t);
    final size = t.getSize(find.bySemanticsLabel('Pink'));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('shows storage used and song count', (t) async {
    await openSettings(t);
    expect(find.text('Storage Used'), findsOneWidget);
    expect(find.text('411 MB'), findsOneWidget);
    expect(find.text('Songs'), findsWidgets);
    expect(find.text('47'), findsOneWidget);
  });

  testWidgets('shows the version from package info', (t) async {
    await openSettings(t);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('9.8.7'), findsOneWidget);
  });
}
