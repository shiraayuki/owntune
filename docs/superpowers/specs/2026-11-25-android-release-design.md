# Android APK in releases (Distribution, part 2)

Approved 2026-11-25 ("mach dich an den apk workflow"); the outline was agreed earlier in the distribution plan.

## Why

The download page's Android button points to `releases/latest/download/owntune.apk`. Releases so far carry only the iOS build. Android users need a signed APK that installs over the previous one.

## Decided (user)

- A signed universal `owntune.apk` is attached to the same GitHub release as `owntune.ipa`, built on every `v*` tag.
- Claude generates the signing keystore and stores it in GitHub secrets; the user keeps a backup (losing it means users must uninstall to update).

## Decided (Claude's calls, stated to the user)

- **One release, created once:** `release.yml` ("Release") runs on `v*` tags, calls the iOS and Android builds as reusable workflows in parallel, and only then creates the release with `owntune.ipa`, `owntune.apk` and `source.json` in one step. The release never exists half-filled, so `releases/latest/download/source.json` (SideStore) and `…/owntune.apk` (page) never 404 during a release. `ios.yml` and the new `android.yml` stay runnable by hand for test builds (artifact only).
- **Build number from the version:** `major*10000 + minor*100 + patch` (0.8.2 → 802) for both platforms, instead of the run number (the new workflow's run number would restart at 1; iOS builds so far were 25–27, so 802 still increases).
- **Signing:** `android/app/build.gradle.kts` signs release builds with the keystore from env vars (`OWNTUNE_KEYSTORE`, `OWNTUNE_KEYSTORE_PASSWORD`, `OWNTUNE_KEY_ALIAS`, `OWNTUNE_KEY_PASSWORD`) or a local `android/key.properties`; without either it falls back to the debug key, so CI's APK build and local builds keep working. The Android workflow fails when the secrets are missing and checks the APK's certificate is not the debug one.
- **Keystore:** PKCS12, RSA 4096, valid 10,000 days, alias `owntune`; the local copy lives outside the repo in `~/.local/share/owntune-signing/` (mode 600) with its password; secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- **ABIs:** all three (arm, arm64, x86_64), as `flutter build apk --release` builds by default. With `--target-platform android-arm,android-arm64` some packages (jni, the Rust crate via cargokit) still put x86_64 libraries into the APK without `libflutter.so`, which would crash on x86_64 devices.
- **Fix on the way:** `tool/sidestore_source.dart` points `iconURL` to `AppIcon.png` (the old `Icon-App-1024x1024@1x.png` was removed with the new icon).

## Non-goals

No Play Store, no split APKs, no Obtainium metadata, no in-app update check (part 3).
