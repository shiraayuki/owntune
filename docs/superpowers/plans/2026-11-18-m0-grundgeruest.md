# M0: Grundgerüst – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Leere Flutter-App `owntune` mit Rust-Kern (`lofty`), die unter Linux läuft, in der CI als APK und unsignierte `.ipa` gebaut wird und per Sideload auf dem iPhone startet.

**Architecture:** Flutter-Projekt mit den Plattformen iOS/Android/Linux. Rust-Crate in `rust/`, angebunden über flutter_rust_bridge v2 (`integrate`, Build über cargokit beim normalen `flutter build`). Ein Startbildschirm zeigt das Ergebnis eines Rust-Aufrufs oder, falls der Rust-Kern nicht lädt, die Fehlermeldung. Zwei GitHub-Actions-Workflows: Linux (Prüfungen + APK) und macOS (`.ipa`).

**Tech Stack:** Flutter (stable), Dart, Rust (stable, rustup), flutter_rust_bridge v2, lofty, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-18-m0-grundgeruest-design.md`

## Global Constraints

- Plattformen: iOS, Android, Linux. Keine weiteren (`--platforms ios,android,linux`).
- Bundle-ID / Application-ID: `dev.owntune.app` (iOS `PRODUCT_BUNDLE_IDENTIFIER`, Android `applicationId`, Linux `APPLICATION_ID`).
- Rust-Crate liegt in `rust/`; generierter flutter_rust_bridge-Code wird eingecheckt.
- `flutter_rust_bridge` (Dart-Paket), `flutter_rust_bridge` (Rust-Crate) und `flutter_rust_bridge_codegen` haben **exakt dieselbe Version**, festgepinnt (kein `^`).
- Flutter-Version in der CI ist festgepinnt und gleich der lokal installierten.
- Keine Pakete aus späteren Meilensteinen (kein drift, Riverpod, just_audio, file_picker).
- Repo: öffentlich, `owntune`, Hauptzweig `main`.
- Lokal kein Android-SDK; Android wird nur in der CI gebaut.

## Review Focus

1. **Rust-Bibliothek lädt auf dem iPhone nicht** (fehlendes Framework, falsche Architektur, Hash-Mismatch) → die App darf nicht mit weißem Bildschirm abstürzen, sondern muss die Fehlermeldung anzeigen; ohne Mac ist das die einzige Diagnose. Test: Task 4, `loadCoreStatus` mit werfendem `init`.
2. **Rust-API geändert, Codegen vergessen** → CI schlägt fehl statt veralteten Code zu bauen. Test: Task 5, Codegen-Check-Schritt.
3. **Versionen von FRB-Dart-Paket, -Crate und -Codegen auseinander** → Laufzeitfehler beim `RustLib.init`. Test: Task 3, Schritt „Versionen prüfen“.
4. **`.ipa` enthält Simulator-Build oder keinen Rust-Code** → CI grün, App auf dem Gerät kaputt. Test: Task 6, Artifact-Inhalt prüfen.
5. **Frischer Checkout baut nicht** (lokal generierte Dateien nicht eingecheckt, `rust/target` versehentlich eingecheckt) → CI baut von sauberem Checkout; Task 3 prüft `git status` auf `target/`.

---

### Task 1: Lokale Werkzeuge installieren

Kein Code, kein Commit. Systempakete brauchen `sudo` → diese Schritte führt der Nutzer selbst aus (Vorschlag: `! <befehl>` im Prompt).

**Interfaces:**
- Produces: `flutter`, `dart`, `cargo`, `rustup`, `cmake`, `ninja`, `flutter_rust_bridge_codegen` im `PATH`.

- [ ] **Step 1 (Nutzer):** `sudo pacman -S --needed cmake ninja rustup`
- [ ] **Step 2:** `rustup default stable`
- [ ] **Step 3:** Flutter stable per Git-Checkout nach `~/.local/share/flutter` installieren (`git clone https://github.com/flutter/flutter.git -b stable --depth 1`), `~/.local/share/flutter/bin` in `~/.bashrc` zum `PATH` hinzufügen. Installierte Version notieren (`flutter --version`) – sie wird in Task 5/6 gepinnt.
- [ ] **Step 4:** `flutter config --no-enable-web --no-enable-macos-desktop --no-enable-windows-desktop`
- [ ] **Step 5:** Aktuelle stabile Version von flutter_rust_bridge v2 auf crates.io nachsehen und genau diese installieren: `cargo install flutter_rust_bridge_codegen --version <X.Y.Z> --locked`. Version notieren – sie gilt projektweit (Global Constraints).
- [ ] **Step 6: Verifizieren**

Run: `flutter doctor`
Expected: `Flutter` und `Linux toolchain` mit ✓. Android/Chrome/Xcode dürfen fehlen.

Run: `flutter_rust_bridge_codegen --version`
Expected: notierte Version.

---

### Task 2: Flutter-Projekt anlegen, Git und Bundle-IDs

**Files:**
- Create: Flutter-Projekt im Repo-Root (`pubspec.yaml`, `lib/`, `test/`, `ios/`, `android/`, `linux/`, `.gitignore`, `analysis_options.yaml`)
- Modify: `ios/Runner.xcodeproj/project.pbxproj`, `android/app/build.gradle.kts`, `linux/CMakeLists.txt`
- Add to Git: `CLAUDE.md`, `docs/`

**Interfaces:**
- Produces: Flutter-Paketname `owntune`.

- [ ] **Step 1:** Im Repo-Root: `flutter create --org dev.owntune --project-name owntune --platforms ios,android,linux .` (bestehende `CLAUDE.md` und `docs/` bleiben unberührt.)
- [ ] **Step 2:** Bundle-IDs auf `dev.owntune.app` setzen: in `project.pbxproj` jedes `dev.owntune.owntune` → `dev.owntune.app` (inkl. `.RunnerTests`); in `android/app/build.gradle.kts` (bzw. `build.gradle`) nur `applicationId` (namespace und Kotlin-Package bleiben); in `linux/CMakeLists.txt` `APPLICATION_ID`.
- [ ] **Step 3: Verifizieren**

Run: `grep -rn "dev.owntune" ios/Runner.xcodeproj/project.pbxproj android/app/build.gradle.kts linux/CMakeLists.txt`
Expected: `PRODUCT_BUNDLE_IDENTIFIER`, `applicationId`, `APPLICATION_ID` zeigen `dev.owntune.app`; nur `namespace` darf `dev.owntune.owntune` sein.

Run: `flutter test && flutter build linux`
Expected: Default-Widget-Test PASS, Build erfolgreich.

- [ ] **Step 4: Git anlegen und committen**

```bash
git init -b main
git add .
git commit -m "chore: Flutter-Grundgerüst für iOS, Android und Linux"
```

---

### Task 3: Rust-Kern mit lofty

**Files:**
- Create (per `flutter_rust_bridge_codegen integrate`): `rust/`, `rust_builder/`, `flutter_rust_bridge.yaml`, `lib/src/rust/` (generiert), `integration_test/`, `test_driver/`
- Create: `rust/src/api/metadata.rs`
- Modify: `rust/src/api/mod.rs`, `rust/Cargo.toml`, `pubspec.yaml`
- Delete: Template-Beispiel `rust/src/api/simple.rs` bzw. dessen `greet` (die `init_app`-Funktion bleibt, ggf. nach `mod.rs`/eigene Datei verschieben)

**Interfaces:**
- Produces (Rust): `#[flutter_rust_bridge::frb(sync)] pub fn supported_formats() -> Vec<String>`
- Produces (Dart, generiert): `List<String> supportedFormats()` aus `package:owntune/src/rust/api/metadata.dart`; `RustLib.init()` aus `package:owntune/src/rust/frb_generated.dart`

- [ ] **Step 1:** Im Repo-Root `flutter_rust_bridge_codegen integrate` ausführen. Danach `lib/main.dart` wieder auf den Stand vor `integrate` zurücksetzen, falls es überschrieben wurde (UI kommt in Task 4).
- [ ] **Step 2:** `lofty` (aktuelle stabile Version, gepinnt) in `rust/Cargo.toml` aufnehmen. `flutter_rust_bridge` in `rust/Cargo.toml` und `pubspec.yaml` auf exakt die Codegen-Version aus Task 1 pinnen (`=X.Y.Z` bzw. `X.Y.Z`).
- [ ] **Step 3: Failing test schreiben** in `rust/src/api/metadata.rs`

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supported_formats_lists_m1_formats_in_order() {
        assert_eq!(supported_formats(), vec!["mp3", "m4a", "flac", "ogg", "wav"]);
    }
}
```

- [ ] **Step 4:** `cd rust && cargo test` → Expected: FAIL (`supported_formats` nicht definiert).
- [ ] **Step 5: Implementieren** `pub fn supported_formats() -> Vec<String>`: feste Kandidatenliste `["mp3", "m4a", "flac", "ogg", "wav"]`, gefiltert über `lofty::file::FileType::from_ext(ext).is_some()` (genauen Pfad in der lofty-Doku der gepinnten Version prüfen). Damit wird lofty wirklich gelinkt und aufgerufen.
- [ ] **Step 6:** `cd rust && cargo test && cargo clippy -- -D warnings && cargo fmt --check` → Expected: PASS, keine Warnungen.
- [ ] **Step 7:** `flutter_rust_bridge_codegen generate` → Expected: `lib/src/rust/api/metadata.dart` enthält `supportedFormats`.
- [ ] **Step 8: Versionen prüfen**

Run: `grep -n "flutter_rust_bridge" pubspec.yaml rust/Cargo.toml && flutter_rust_bridge_codegen --version`
Expected: dreimal dieselbe Version, ohne `^`.

- [ ] **Step 9:** `flutter build linux` → Expected: erfolgreich (cargokit baut den Rust-Kern mit).
- [ ] **Step 10: Commit**

Run zuerst: `git status --porcelain | grep target/` → Expected: keine Ausgabe.

```bash
git add .
git commit -m "feat: Rust-Kern mit lofty über flutter_rust_bridge"
```

---

### Task 4: Startbildschirm mit Rust-Status

**Files:**
- Create: `lib/app/core_status.dart`, `lib/app/home_screen.dart`
- Modify: `lib/main.dart`
- Test: `test/app/core_status_test.dart`, `test/app/home_screen_test.dart`, `integration_test/core_test.dart` (ersetzt das Template-Integrationstest-Beispiel)
- Delete: `test/widget_test.dart` (Counter-Template)

**Interfaces:**
- Consumes: `RustLib.init()`, `supportedFormats()` aus Task 3
- Produces:
  - `sealed class CoreStatus`; `final class CoreReady extends CoreStatus { final List<String> formats; }`; `final class CoreFailed extends CoreStatus { final String message; }`
  - `Future<CoreStatus> loadCoreStatus({Future<void> Function()? init, List<String> Function()? formats})` – Defaults: `RustLib.init` bzw. `supportedFormats`; fängt **jede** Exception/Error und liefert `CoreFailed(e.toString())`
  - `class HomeScreen extends StatelessWidget { const HomeScreen({super.key, required CoreStatus status}); }`
  - `class OwntuneApp extends StatelessWidget { const OwntuneApp({super.key, required CoreStatus status}); }` (MaterialApp, `title: 'owntune'`, `home: HomeScreen`)

- [ ] **Step 1: Failing tests schreiben** `test/app/core_status_test.dart`

```dart
test('loadCoreStatus liefert Formate, wenn Rust lädt', () async {
  final s = await loadCoreStatus(init: () async {}, formats: () => ['mp3', 'flac']);
  expect(s, isA<CoreReady>());
  expect((s as CoreReady).formats, ['mp3', 'flac']);
});

test('loadCoreStatus liefert Fehler statt Absturz, wenn init wirft', () async {
  final s = await loadCoreStatus(init: () async => throw StateError('lib fehlt'), formats: () => []);
  expect(s, isA<CoreFailed>());
  expect((s as CoreFailed).message, contains('lib fehlt'));
});

test('loadCoreStatus liefert Fehler, wenn der Rust-Aufruf wirft', () async {
  final s = await loadCoreStatus(init: () async {}, formats: () => throw Exception('panic'));
  expect(s, isA<CoreFailed>());
});
```

`test/app/home_screen_test.dart`:

```dart
testWidgets('zeigt App-Namen und Formate', (t) async {
  await t.pumpWidget(const OwntuneApp(status: CoreReady(['mp3', 'flac'])));
  expect(find.text('owntune'), findsOneWidget);
  expect(find.text('Rust-Kern: OK'), findsOneWidget);
  expect(find.text('mp3, flac'), findsOneWidget);
});

testWidgets('zeigt Fehlermeldung, wenn Rust nicht lädt', (t) async {
  await t.pumpWidget(const OwntuneApp(status: CoreFailed('lib fehlt')));
  expect(find.text('Rust-Kern: Fehler'), findsOneWidget);
  expect(find.textContaining('lib fehlt'), findsOneWidget);
});
```

(Die `CoreReady`/`CoreFailed`-Konstruktoren sind `const`.)

- [ ] **Step 2:** `flutter test test/app` → Expected: FAIL (Klassen fehlen).
- [ ] **Step 3: Implementieren** `core_status.dart` und `home_screen.dart` gemäß Interfaces. Texte exakt: `owntune`, `Rust-Kern: OK`, Formate mit `', '` verbunden, `Rust-Kern: Fehler`, darunter die Meldung als auswählbarer Text (`SelectableText`), damit sie auf dem iPhone kopierbar ist.
- [ ] **Step 4:** `lib/main.dart`: `WidgetsFlutterBinding.ensureInitialized()`, `final status = await loadCoreStatus();`, `runApp(OwntuneApp(status: status));`
- [ ] **Step 5:** `flutter test` → Expected: alle PASS. `flutter analyze` → Expected: `No issues found!`
- [ ] **Step 6: Integrationstest mit echtem Rust** `integration_test/core_test.dart`

```dart
testWidgets('echter Rust-Kern liefert die M1-Formate', (t) async {
  final s = await loadCoreStatus();
  expect(s, isA<CoreReady>());
  expect((s as CoreReady).formats, ['mp3', 'm4a', 'flac', 'ogg', 'wav']);
});
```

(mit `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`)

Run: `flutter test integration_test -d linux` → Expected: PASS.

- [ ] **Step 7:** `flutter run -d linux` → Expected: Fenster zeigt `owntune`, `Rust-Kern: OK`, `mp3, m4a, flac, ogg, wav`.
- [ ] **Step 8: Commit**

```bash
git add .
git commit -m "feat: Startbildschirm zeigt Status des Rust-Kerns"
```

---

### Task 5: GitHub-Repo und Linux-CI

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: Workflow `CI`, Job `linux`; Artifact `owntune-apk`.

- [ ] **Step 1:** `ci.yml`, Trigger `push` und `pull_request`. Job `linux` auf `ubuntu-latest`:
  1. `actions/checkout`
  2. Flutter über `subosito/flutter-action` mit **der lokal notierten Flutter-Version**, Cache an
  3. Rust stable über `dtolnay/rust-toolchain` mit `components: clippy, rustfmt`; Cargo-Cache (`Swatinem/rust-cache`, `workspaces: rust`)
  4. `sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev xvfb`
  5. `actions/setup-java` (Temurin 17)
  6. `flutter pub get`, `flutter analyze`, `flutter test`
  7. In `rust/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`
  8. Codegen-Check: `flutter_rust_bridge_codegen` in **derselben Version** installieren (`cargo install --locked` oder `cargo binstall`), `flutter_rust_bridge_codegen generate`, dann `git diff --exit-code`
  9. `xvfb-run flutter test integration_test -d linux`
  10. `flutter build apk --release`, APK als Artifact `owntune-apk` hochladen
- [ ] **Step 2: Repo anlegen und pushen**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: Linux-Prüfungen und Android-Build"
gh repo create owntune --public --source . --push
```

- [ ] **Step 3: Verifizieren**

Run: `gh run watch --exit-status`
Expected: Job `linux` erfolgreich, Artifact `owntune-apk` vorhanden (`gh run view --log` bei Fehlern). Fehler beheben, committen, erneut pushen, bis grün.

- [ ] **Step 4: Codegen-Check gegenprüfen:** auf einem Wegwerf-Branch in `metadata.rs` eine zusätzliche `pub fn ping() -> String` ergänzen, **ohne** `generate` committen und pushen → Expected: Codegen-Check-Schritt schlägt fehl. Danach lokal zurück auf `main`, Branch lokal und remote löschen (`git push origin --delete <branch>`).

---

### Task 6: iOS-CI mit unsignierter `.ipa`

**Files:**
- Create: `.github/workflows/ios.yml`

**Interfaces:**
- Produces: Workflow `iOS`, Artifact `owntune-ipa` mit `owntune.ipa`.

- [ ] **Step 1:** `ios.yml`, Trigger `push` auf `main` und `workflow_dispatch`. Job `ios` auf `macos-latest`:
  1. `actions/checkout`
  2. Flutter (gleiche gepinnte Version wie in `ci.yml`)
  3. Rust stable mit `targets: aarch64-apple-ios`; Cargo-Cache für `rust`
  4. `flutter pub get`
  5. `flutter build ios --release --no-codesign`
  6. `mkdir Payload && cp -R build/ios/iphoneos/Runner.app Payload/ && zip -qr owntune.ipa Payload`
  7. `owntune.ipa` als Artifact `owntune-ipa` hochladen
- [ ] **Step 2: Commit und push**

```bash
git add .github/workflows/ios.yml
git commit -m "ci: unsignierte iOS-.ipa auf macOS bauen"
git push
```

- [ ] **Step 3:** `gh run watch --exit-status` (iOS-Run) → Expected: erfolgreich.
- [ ] **Step 4: Artifact-Inhalt prüfen**

`IPA` = Download-Ordner im Session-Scratchpad (z. B. `<scratchpad>/ipa`), nicht im Repo.

Run: `gh run download <run-id> -n owntune-ipa -D "$IPA" && unzip -l "$IPA/owntune.ipa" | grep -E "Payload/Runner.app/(Runner|Info.plist)$|rust_lib_owntune"`
Expected: `Runner`-Binary, `Info.plist` und ein Eintrag mit `rust_lib_owntune`. Falls der Rust-Kern statisch ins Runner-Binary gelinkt ist und kein eigener Eintrag erscheint: `unzip -p "$IPA/owntune.ipa" Payload/Runner.app/Runner | strings | grep -c frbgen_owntune` → Expected: > 0.

Run: `unzip -p "$IPA/owntune.ipa" Payload/Runner.app/Info.plist | python3 -I -c "import plistlib,sys; p=plistlib.load(sys.stdin.buffer); print(p['CFBundleIdentifier'], p.get('CFBundleSupportedPlatforms'))"`
Expected: `dev.owntune.app ['iPhoneOS']` (nicht `iPhoneSimulator`).

---

### Task 7: Abnahme auf dem iPhone und CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1 (Nutzer):** `owntune.ipa` aus dem letzten iOS-Run per SideStore/iloader auf das iPhone installieren und starten.
Expected: Bildschirm zeigt `owntune`, `Rust-Kern: OK`, `mp3, m4a, flac, ogg, wav`. Bei `Rust-Kern: Fehler` den angezeigten Text kopieren und zurückmelden → als Bug behandeln, nicht als erledigt.
- [ ] **Step 2:** `CLAUDE.md` an den echten Stand anpassen: „Stand“-Absatz (M0 erledigt), echte Befehle (inkl. `flutter_rust_bridge_codegen generate`, `cargo test` in `rust/`, `flutter test integration_test -d linux`), gepinnte Versionen und wo sie stehen, Hinweis auf die beiden Workflows und das `.ipa`-Artifact, offene Frage 1 als entschieden markieren.
- [ ] **Step 3: Commit und push**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md auf Stand nach M0"
git push
```
