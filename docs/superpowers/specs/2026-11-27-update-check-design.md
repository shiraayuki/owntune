# In-app update check (v0.11.0)

## Why

owntune is sideloaded (SideStore on iOS, a signed APK on Android). Neither
tells the user reliably that a new version exists, so people keep running
old builds. The app should notice a newer GitHub release by itself and say
so. This finishes the Distribution milestone (its last open part).

## Decided by the user

- **Automatic, at most once a day, can be switched off in Settings**
  (2026-11-25, "option B"). README and download page say openly that the
  app asks GitHub once a day for updates.
- **Variant A** (2026-11-27): a dismissible banner at the top of Home, plus
  the Settings "Version" row showing the new version.
- The short design below was approved as a whole on 2026-11-27.

## Goals

- A newer release shows as a banner on Home within a day of being published
  (on the next start or return to the app).
- One tap leads to the update: the APK download on Android, SideStore (or
  the download page) on iOS.
- Dismissing hides the banner for that version only; a later version shows
  again.
- The check can be turned off; then the app makes no update request at all.

## Non-goals

- No "what's new" text: release notes are only a generated changelog link.
- No in-app download or install of the APK.
- No check on Linux (dev aid; the local pubspec version is not the release
  version, so the banner would always show).

## Anti-goals

- A failing or slow check must never show an error, block startup or
  disturb playback. No network → nothing happens, try again next time.
- No nagging: one banner, no dialogs, no badges elsewhere.

## Approaches

1. **GitHub API `releases/latest`** (chosen): `GET
   https://api.github.com/repos/shiraayuki/owntune/releases/latest`, read
   `tag_name` (`vX.Y.Z`). The site already uses this endpoint; drafts and
   pre-releases are excluded by GitHub; one request a day is far below the
   unauthenticated limit (60/h per IP).
2. `releases/latest/download/source.json` (the SideStore source): also has
   the version, but goes through redirects and exists only for SideStore's
   sake. No advantage.
3. Scraping the download page: fragile, rejected.

## Design

### Check

- `UpdateChecker` (pure logic, injected `HttpTransport`, clock and store)
  compares the release tag with the running version
  (`appVersionProvider`, `package_info_plus`) as `major.minor.patch`
  integers. A tag that does not parse is ignored (no update).
- Runs on startup and whenever the app returns to the foreground, only
  when the switch is on, the platform is iOS or Android, and the last
  **successful** check is 24 h or more ago. A failed check (no network,
  HTTP error, bad JSON) stores nothing and stays silent.
- Persisted in `settings_entries` through a small store (pattern of
  `SoundcloudClientIdStore`): last check time, latest version found,
  dismissed version. Not part of `AppSettings` (they change without user
  action).
- The switch `checkForUpdates` (default on; only an explicit `false` turns
  it off) is part of `AppSettings`. Turning it on checks at once (ignoring
  the 24 h); turning it off hides the banner and the Settings hint.
- An "available" update = latest found > running version. After the user
  installs it, the running version catches up and nothing shows.

### Banner (Home)

- At the top of the Home tab, above the For You | Stats text tabs, so both
  sub-tabs show it. Flat, in the app's style (no gradients):
  "owntune 0.11.0 is available", an "Update" action and a ✕.
- ✕ stores that version as dismissed; the banner shows again only for a
  newer version. The banner is hidden while the version equals the
  dismissed one.

### Update target

- Android: open
  `https://github.com/shiraayuki/owntune/releases/latest/download/owntune.apk`
  in the browser (external application).
- iOS: try `sidestore://`; if it cannot be opened, open the download page
  `https://shiraayuki.github.io/owntune/`.
- New dependency: `url_launcher`. iOS needs `sidestore` in
  `LSApplicationQueriesSchemes` only if `canLaunchUrl` is used; the builder
  may instead rely on `launchUrl` returning false.
- A failing launch is ignored silently.

### Settings → About

- New switch cell "Check for Updates" (above or below "Version"), group
  foot "Asks GitHub once a day for a new version."
- The "Version" row shows "0.10.0 · 0.11.0 available" while an update is
  available (independent of the banner's dismissal) and opens the update
  target on tap; otherwise it stays a plain row.

### Copy

- README: the "No tracking" line says the app asks GitHub once a day for a
  new version (can be switched off in Settings); the update section mentions
  the in-app notice.
- Site: FAQ "Does owntune send anything about me anywhere?" says the same;
  the Android step about new versions mentions the in-app notice.
- CLAUDE.md: status line for v0.11.0, Distribution milestone done.

### Tests

- Unit: version parsing/compare, the 24 h rule, failure stores nothing,
  dismissal, switch on → immediate check.
- Widget: banner shows / hides on ✕ / hides when switched off; Settings
  row and switch. Fakes for the transport, the store and the launcher;
  `pumpApp` keeps the checker inert by default.

## Left to the builder

- Exact banner layout (follow the existing Home cards and colours), the
  placement of the switch within About, file and class names, how the
  foreground trigger is wired (e.g. `AppLifecycleListener` like the
  loudness measurer).
