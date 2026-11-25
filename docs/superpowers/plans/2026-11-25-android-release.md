# Android Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every `v*` tag produces one GitHub release with `owntune.ipa`, a signed `owntune.apk` and `source.json`.

**Architecture:** `release.yml` calls `ios.yml` and `android.yml` (both `workflow_call` + `workflow_dispatch`) and publishes their artifacts in one `gh release create`. Gradle reads the release keystore from env vars or `android/key.properties`.

**Tech Stack:** GitHub Actions, Gradle Kotlin DSL, keytool/apksigner, Dart (`tool/sidestore_source.dart`).

**Spec:** `docs/superpowers/specs/2026-11-25-android-release-design.md`

## Global Constraints

- Build number = `major*10000 + minor*100 + patch` from the tag `vX.Y.Z`; build name `X.Y.Z`.
- No secret or keystore in the repo (`*.jks`, `key.properties` are git-ignored).
- Existing `flutter build apk --release` in CI must keep working without secrets (debug key).

## Review Focus

- A tag push where one build fails: no release is created (nothing half-published).
- Missing secrets in the Android workflow: it fails loudly instead of shipping a debug-signed APK.
- Manual `gh workflow run iOS` / `Android`: artifact only, never a release.
- The SideStore `buildVersion` and the iOS bundle's build number are the same number.
- Local `flutter run` / `flutter build apk` without a keystore still work.

---

### Task 1: Gradle signing + local keystore + secrets

- [x] `android/app/build.gradle.kts`: `release` signing config from env / `key.properties`, else debug.
- [x] Generate the keystore into `~/.local/share/owntune-signing/`; set the four secrets with `gh secret set` (done by the user; the auto mode blocked it).
- [x] Build locally with the env vars; `apksigner verify --print-certs` shows the owntune certificate.
- [x] Commit `build: sign Android release builds with the owntune key when it is configured`.

### Task 2: Workflows

- [x] `android.yml`: build-number step, keystore from secret, `flutter build apk --release --build-name --build-number` (all ABIs, see the spec), verify certificate, upload artifact `owntune-apk` (`owntune.apk`).
- [x] `ios.yml`: `workflow_call` with `runner` input; build number from the tag; drop its release step; artifact `owntune-ipa`.
- [x] `release.yml`: on `v*` tags; jobs `ios`, `android` (reusable, `secrets: inherit`), `publish` (needs both): download artifacts, `tool/sidestore_source.dart` with the build number, `gh release create` with all three files.
- [x] `tool/sidestore_source.dart`: `iconURL` → `AppIcon.png`; test updated.
- [x] `actionlint` if available (it was not; YAML parsed, checked by hand); commit `ci: one release with the iPhone and Android builds`.

### Task 3: Docs

- [x] CLAUDE.md: release section (Release workflow, build numbers, signing, where the keystore lives, `gh workflow run Android`).
- [x] README install section mentions the APK if it does not yet.
- [x] Commit `docs: Android release`.
