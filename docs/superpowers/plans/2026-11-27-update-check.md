# Update Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** owntune asks GitHub at most once a day for a newer release and shows it as a dismissible banner on Home and in Settings → About, with one tap to the update.

**Architecture:** A new `lib/update/` folder: pure version parsing and the GitHub fetch, a `settings_entries`-backed `UpdateStore`, an `UpdateController` Riverpod notifier that applies the once-a-day rule and listens to the app lifecycle and the new `checkForUpdates` setting, an `UpdateLauncher` behind an interface (url_launcher), and the `UpdateBanner` widget. Everything is inert unless `updateCheckSupportedProvider` is true (iOS/Android), so Linux and `pumpApp` never make a request.

**Tech Stack:** Flutter 3.50 / Dart 3.14, flutter_riverpod 3 (no codegen), drift, the existing `HttpTransport`, new `url_launcher`.

**Spec:** `docs/superpowers/specs/2026-11-27-update-check-design.md`

## Global Constraints

- Everything in English (code, comments, UI strings, commits). Imports: `package:material_ui/material_ui.dart`, `package:cupertino_ui/cupertino_ui.dart` (never `flutter/material.dart` / `flutter/cupertino.dart`).
- Endpoint: `https://api.github.com/repos/shiraayuki/owntune/releases/latest`, header `Accept: application/vnd.github+json`, `service: 'GitHub'`; read `tag_name`.
- Android target: `https://github.com/shiraayuki/owntune/releases/latest/download/owntune.apk`. iOS: `sidestore://`, fallback `https://shiraayuki.github.io/owntune/`. Both opened in an external application.
- At most one successful check per 24 h; a failed check stores nothing and shows nothing.
- No check on Linux and in widget tests (`updateCheckSupportedProvider` false).
- Banner text exactly `owntune <x.y.z> is available`, action `Update`, dismiss tooltip `Dismiss`. Settings: switch `Check for Updates` (default on, only an explicit stored `false` turns it off), foot `Asks GitHub once a day for a new version.`, Version row `<current> · <latest> available` while an update is available.
- Flat visuals, no gradients or glass (user rule).
- `flutter analyze` must report "No issues found!"; `flutter test` green.

## Review Focus

1. **Clock set back** (stored last check lies in the future): the check counts as due, not blocked until that date. → Task 3 test `a last check in the future is due`.
2. **Running build newer than or equal to the latest release** (sideloaded test build, just updated): no banner, no "available". → Task 1 compare test + Task 3 test `no update when the running version is the latest`.
3. **Odd tags and versions** (`v0.11.0-beta`, `nightly`, `0.10.0+1000`): odd tags are ignored without a crash; a build suffix on the running version parses. → Task 1 tests.
4. **Startup and resume fire together**: only one request in flight. → Task 3 test `concurrent checks make one request`.
5. **Offline or HTTP 403 (rate limit)**: silent, nothing stored, the next resume tries again. → Task 3 test `a failed check stores nothing and retries on resume`.

---

### Task 1: Version parsing and the release fetch

**Files:**
- Create: `lib/update/app_version.dart`, `lib/update/latest_release.dart`
- Test: `test/update/app_version_test.dart`, `test/update/latest_release_test.dart`

**Interfaces:**
- Produces:
  - `class AppVersion implements Comparable<AppVersion>` with `final int major, minor, patch`, `const AppVersion(this.major, this.minor, this.patch)`, `static AppVersion? parse(String text)`, `compareTo`, `operator >`, `==`/`hashCode`, `toString()` → `'0.11.0'`.
  - `const kLatestReleaseApi`, `kApkUrl`, `kSideStoreUrl`, `kDownloadPageUrl` (Strings, values from Global Constraints).
  - `Future<AppVersion?> fetchLatestRelease(HttpTransport http)`: getJson on `kLatestReleaseApi`; returns `AppVersion.parse(tag_name)` or null when `tag_name` is missing / not a String / does not parse. Network and HTTP errors propagate (the controller swallows them).

- [ ] **Step 1: Write the failing tests**

```dart
test('parses tags and plain versions', () {
  expect(AppVersion.parse('v0.11.0'), const AppVersion(0, 11, 0));
  expect(AppVersion.parse('0.10.0'), const AppVersion(0, 10, 0));
  expect(AppVersion.parse('0.10.0+1000'), const AppVersion(0, 10, 0));
  expect(AppVersion.parse(' v1.2.3 '), const AppVersion(1, 2, 3));
});
test('rejects anything else', () {
  for (final s in ['v0.11.0-beta', 'nightly', '0.11', '', 'v0.11.x']) {
    expect(AppVersion.parse(s), isNull, reason: s);
  }
});
test('compares numerically, not as text', () {
  expect(const AppVersion(0, 10, 0) > const AppVersion(0, 9, 2), isTrue);
  expect(const AppVersion(1, 0, 0) > const AppVersion(0, 99, 99), isTrue);
  expect(const AppVersion(0, 10, 0) > const AppVersion(0, 10, 0), isFalse);
  expect(const AppVersion(0, 11, 0).toString(), '0.11.0');
});
```

`latest_release_test.dart` with `FakeHttpTransport(onGet: ...)` answering JSON:
- `{"tag_name": "v0.11.0"}` → `AppVersion(0, 11, 0)`, request URL == `kLatestReleaseApi`, headers contain `Accept: application/vnd.github+json`.
- `{"tag_name": 5}` and `{}` → null.
- status 403 → throws `HttpStatusError`.

(`FakeHttpTransport.getJson` does not pass headers to the test; extend it to record `(url, headers)` of getJson calls in a new `jsonGets` list, keeping `gets` as is.)

- [ ] **Step 2: Run** `flutter test test/update/` → FAIL (files missing).
- [ ] **Step 3: Implement** both files. Parse with `RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(\+\d+)?$')` on the trimmed text.
- [ ] **Step 4: Run** `flutter test test/update/` → PASS.
- [ ] **Step 5: Commit** `feat: parse release versions and fetch the latest GitHub release`

---

### Task 2: The switch setting and the update store

**Files:**
- Modify: `lib/settings/settings.dart` (field, copyWith, ==, hashCode, load/save key `check_updates`)
- Create: `lib/update/update_store.dart`
- Test: `test/settings/settings_test.dart`, `test/update/update_store_test.dart`
- Modify: `test/support/fakes.dart` (`MemoryUpdateStore`)

**Interfaces:**
- Produces:
  - `AppSettings.checkForUpdates` (`bool`, default `true`).
  - `class UpdateRecord { const UpdateRecord({this.lastCheck, this.latest, this.dismissed}); final DateTime? lastCheck; final AppVersion? latest, dismissed; UpdateRecord copyWith(...) }`.
  - `abstract interface class UpdateStore { Future<UpdateRecord> read(); Future<void> write(UpdateRecord record); }`
  - `class DbUpdateStore implements UpdateStore` (`DbUpdateStore(AppDatabase db)`), keys `update_last_check` (milliseconds since epoch, UTC), `update_latest`, `update_dismissed` (`'0.11.0'`); malformed values read as null; `write` upserts all three in one batch and deletes a key whose value is null.
  - In fakes: `class MemoryUpdateStore implements UpdateStore { MemoryUpdateStore([this.record = const UpdateRecord()]); UpdateRecord record; int writes = 0; }`.

- [ ] **Step 1: Write failing tests**
  - settings: `checkForUpdates round-trips and defaults to on` (empty DB → true; save false → load false; stored `'garbage'` → true).
  - store (in-memory `AppDatabase` as in `settings_test.dart`): empty → all null; write then read round-trips (DateTime equal to the millisecond); writing `dismissed: null` after a value removes it; a row `update_latest = 'x'` reads as null.
- [ ] **Step 2: Run** `flutter test test/settings/settings_test.dart test/update/update_store_test.dart` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same → PASS.
- [ ] **Step 5: Commit** `feat: store the update check state and the Check for Updates switch`

---

### Task 3: UpdateController

**Files:**
- Create: `lib/update/update_controller.dart`
- Modify: `lib/app/app_shell.dart` (watch the controller next to `loudnessMeasurerProvider`), move `appVersionProvider` from `lib/settings/settings_sheet.dart` to `lib/app/providers.dart` (so `lib/update/` does not import a widget file; fix imports), `test/support/fakes.dart` (`pumpApp`: override `updateStoreProvider` with `MemoryUpdateStore()`; `updateCheckSupportedProvider` stays false by its test default, see below)
- Test: `test/update/update_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 `AppVersion`, `fetchLatestRelease`; Task 2 `UpdateStore`, `UpdateRecord`, `AppSettings.checkForUpdates`; existing `httpTransportProvider`, `clockProvider`, `appVersionProvider` (moved to `lib/app/providers.dart` in this task), `settingsProvider`, `databaseProvider`.
- Produces:
  - `final updateCheckSupportedProvider = Provider<bool>((ref) => Platform.isIOS || Platform.isAndroid);` — `pumpApp` overrides it with `false` explicitly (Linux tests would already be false, but keep it explicit).
  - `final updateStoreProvider = Provider<UpdateStore>((ref) => DbUpdateStore(ref.watch(databaseProvider)));`
  - `class UpdateInfo { const UpdateInfo({this.current, this.latest, this.dismissed, this.enabled = false}); AppVersion? get available; bool get showBanner; }` — `available` = `latest` when `enabled`, both versions known and `latest > current`, else null; `showBanner` = `available != null && available != dismissed`.
  - `final updateControllerProvider = NotifierProvider<UpdateController, UpdateInfo>(UpdateController.new);`
  - `UpdateController`: `Future<void> check({bool force = false})`, `Future<void> dismiss()`.

Behaviour (pins the tests):
- `build()`: when not supported → `const UpdateInfo()` and nothing else. Otherwise: register an `AppLifecycleListener(onResume: check)` (disposed in `ref.onDispose`); `ref.listen` on `settingsProvider.select((s) => s.checkForUpdates)`: off → state `enabled: false`; off→on → `enabled: true` and `check(force: true)`. Start an async init (read store + `appVersionProvider.future`, set state, then `check()`); a failing version lookup leaves `current` null (no banner).
- `check`: returns at once when disabled or a check is in flight. Due when `force`, no last check, or `now.difference(lastCheck)` is `>= 24 h` **or negative**. On success: store `lastCheck: now, latest: <fetched>` (a null fetch result stores nothing and keeps the old record), update state. Any exception: swallow, store nothing.
- `dismiss`: when `available != null`, store and set `dismissed = available`.

- [ ] **Step 1: Write failing tests** (`testWidgets` so `AppLifecycleListener` has a binding; a `ProviderContainer` with overrides: supported `true`, `MemoryUpdateStore`, `FakeHttpTransport` answering `{"tag_name": "v0.11.0"}` and counting `jsonGets`, `appVersionProvider` → `'0.10.0'`, `clockProvider` → mutable `now`, `initialSettingsProvider`, `settingsRepositoryProvider` → `FakeSettingsRepository`). Keep the container alive with `container.listen(updateControllerProvider, (_, _) {})`; let async work finish with `await t.pump()` / `t.runAsync` as needed.
  - `first start checks and shows the banner`: one request; `available == AppVersion(0,11,0)`, `showBanner`; store has `lastCheck == now`, `latest == 0.11.0`.
  - `within 24 h no second request`: store `lastCheck = now - 23 h` → resume (`t.binding.handleAppLifecycleStateChanged(paused)` then `resumed`) → 0 requests; state still shows the stored `latest`.
  - `after 24 h resume checks again`: `lastCheck = now - 24 h` → 1 request.
  - `a last check in the future is due`: `lastCheck = now + 3 days` → 1 request.
  - `no update when the running version is the latest`: version `'0.11.0'` → `available == null`, no banner.
  - `concurrent checks make one request`: the transport's answer waits on a `Completer`; call `check(force: true)` twice before completing → 1 request.
  - `a failed check stores nothing and retries on resume`: transport throws `OnlineError('No connection')` → no banner, `store.writes == 0`; then answer normally, resume → 1 more request, banner shows.
  - `dismiss hides this version only`: dismiss → `showBanner` false, store `dismissed == 0.11.0`; a later check finds `v0.12.0` (lastCheck 24 h ago, resume) → `showBanner` true.
  - `switch off hides, switch on checks at once`: set `checkForUpdates: false` via `settingsProvider.notifier.set` → `available == null`; set true with `lastCheck = now` → 1 request despite the 24 h.
  - `unsupported platform never asks`: supported `false` → 0 requests, `available == null`.
- [ ] **Step 2: Run** `flutter test test/update/update_controller_test.dart` → FAIL.
- [ ] **Step 3: Implement** the controller; add `ref.watch(updateControllerProvider)` in `OwntuneApp.build` with a one-line comment; add the two `pumpApp` overrides.
- [ ] **Step 4: Run** `flutter test` (whole suite, `pumpApp` changed) → PASS.
- [ ] **Step 5: Commit** `feat: check GitHub once a day for a newer release`

---

### Task 4: Launcher and the Home banner

**Files:**
- Modify: `pubspec.yaml` (`flutter pub add url_launcher`; commit `pubspec.lock`)
- Create: `lib/update/update_launcher.dart`, `lib/update/update_banner.dart`
- Modify: `lib/home/home_screen.dart` (banner above the `TextTabs`), `test/support/fakes.dart` (`FakeUpdateLauncher`, override in `pumpApp`)
- Test: `test/update/update_launcher_test.dart`, `test/update/update_banner_test.dart`

**Interfaces:**
- Consumes: Task 1 URL constants; Task 3 `updateControllerProvider`, `UpdateInfo`.
- Produces:
  - `abstract interface class UpdateLauncher { Future<void> open(); }`
  - `class PlatformUpdateLauncher implements UpdateLauncher { PlatformUpdateLauncher({required bool isIOS, Future<bool> Function(Uri url)? launch}); }` — default `launch` = `launchUrl(url, mode: LaunchMode.externalApplication)`; a throw counts as false. iOS: `sidestore://`, on false the download page. Android: the APK URL. Never throws.
  - `final updateLauncherProvider = Provider<UpdateLauncher>((ref) => PlatformUpdateLauncher(isIOS: Platform.isIOS));`
  - `class UpdateBanner extends ConsumerWidget` (`Key('update-banner')` on its root when shown; `SizedBox.shrink()` otherwise).
  - In fakes: `class FakeUpdateLauncher implements UpdateLauncher { int opened = 0; }`.

- [ ] **Step 1: Write failing tests**
  - launcher: iOS with `launch` returning true for `sidestore://` → opened only `[sidestore://]`; returning false → `[sidestore://, download page]`; throwing on sidestore → falls back to the page, no throw; Android → `[apk url]`.
  - banner (`pumpApp` with `overrides: [updateControllerProvider.overrideWith(() => _StubController(UpdateInfo(...)))]` where the stub records `dismiss` calls and sets `dismissed`): shows `owntune 0.11.0 is available` on the Home tab (also after switching to Stats); `Update` → `FakeUpdateLauncher.opened == 1`; tap tooltip `Dismiss` → `dismiss` called and the banner is gone; with `available == null` → `find.byKey(Key('update-banner'))` finds nothing.
- [ ] **Step 2: Run** `flutter test test/update/` → FAIL.
- [ ] **Step 3: Implement.** Banner: flat card in `OwntuneColors.surface`, radius 12, horizontal margin 16 like the For You cards; leading `CupertinoIcons.arrow_down_circle` in `accent`, text in `text`, `Update` in `accent` (semibold), trailing ✕ (`CupertinoIcons.xmark`, `muted`, tooltip `Dismiss`). Placed in `HomeScreen`'s Column before `TextTabs`.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze` → PASS / "No issues found!".
- [ ] **Step 5: Commit** `feat: update banner on Home`

---

### Task 5: Settings → About

**Files:**
- Modify: `lib/settings/settings_sheet.dart` (`_Cell` gets optional `onTap`; About group: Version row + switch + foot)
- Test: `test/settings/settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 2 `checkForUpdates`; Task 3 `updateControllerProvider`; Task 4 `updateLauncherProvider`, `FakeUpdateLauncher`.

- [ ] **Step 1: Write failing tests**
  - `About has Check for Updates, on by default`: `find.text('Check for Updates')`, switch `Key('check-updates')` value true, foot `Asks GitHub once a day for a new version.`
  - `tapping Check for Updates turns it off and saves it`: last `settingsRepo.saved` has `checkForUpdates == false`.
  - `Version shows an available update and opens it`: stub controller with `available == 0.11.0`, version `'9.8.7'` → text `9.8.7 · 0.11.0 available`; tap → `FakeUpdateLauncher.opened == 1`. Also when the banner was dismissed (`dismissed == available`).
  - Existing `Version` test still shows plain `9.8.7` without an update.
- [ ] **Step 2: Run** `flutter test test/settings/settings_sheet_test.dart` → FAIL.
- [ ] **Step 3: Implement.** Switch icon `CupertinoIcons.arrow_2_circlepath`; switch placed after the Version row in About; `_GroupFoot` below the group.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze` → PASS / "No issues found!".
- [ ] **Step 5: Commit** `feat: Check for Updates in Settings`

---

### Task 6: Copy and docs

**Files:**
- Modify: `README.md:33` ("No tracking" line) and the update section around `README.md:115`; `site/index.html:369` (keep "No tracking." — still true; adjust only if it claims nothing is sent), `site/index.html:506` (Android new-version step), `site/index.html:524` (FAQ); `CLAUDE.md` (status paragraph: v0.11.0 sentence; Distribution done incl. the update check; remove "in-app update check" from the open list; Architecture: add `update/` line; mention `url_launcher` under the stack "In use since v0.11.0").

Copy to use (adapt sentence flow, keep meaning):
- README: "**No tracking.** No account, no analytics. Once a day the app asks GitHub whether there is a new version (you can turn this off in Settings); otherwise the internet is only used when *you* search for a song to download."
- README update section: add "owntune also shows a banner on Home when a new version is out."
- Site FAQ: "No. There is no account and no tracking. Once a day the app asks GitHub whether a new version is out (Settings → Check for Updates turns it off). Otherwise the internet is only used when you search for a song to download."
- Site Android step: "When a new version is out, owntune shows it on Home; tap Update, download it and install it over the old one. Your library stays."

- [ ] **Step 1:** Edit the files.
- [ ] **Step 2:** `grep -n "sends nothing" README.md site/index.html` → no hits.
- [ ] **Step 3: Commit** `docs: update check in README, site and CLAUDE.md`

---

**After all tasks:** one whole-branch review. On the phone: v0.11.0 can only show the banner once a newer release exists, so the first real check is the next release; until then check the Settings switch and the Version row. Whether `sidestore://` opens SideStore is unverified (the fallback to the download page covers it).
