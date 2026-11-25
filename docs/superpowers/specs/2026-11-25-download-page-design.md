# Download page (Distribution, part 1)

Approved 2026-11-25 ("passt so, mach"). Part of the Distribution milestone (see the distribution plan memory): free sharing via SideStore (iPhone) and an APK (Android).

## Why

Friends should find owntune, see what it does and install it without reading the GitHub README. The approved mockup `docs/mockups/distribution-v1/index.html` becomes the real page.

## Decided

- **`site/`** holds the page (`index.html`) and is deployed to GitHub Pages (`shiraayuki.github.io/owntune`) by a workflow `pages.yml` on pushes to main that touch `site/` (and manually). Pages is switched on only together with the first release that has an APK, so the Android button never points nowhere.
- **Phone screens are HTML, not images** (user's choice, "method 3"): the seven screens (home, library, player, playlist, download, edit, stats) live in `site/screens/*.html` with the mockups' shared CSS/JS copied next to them, embedded in the page as iframes. The page's accent picker sends `{mode: 'dark', accent}` to every screen via `postMessage` (the mockups already listen), so the screens recolour with the page.
- **Screens are corrected by hand against the app code** (not the old mockups): text tabs with accent underline (Library, Search Online `Songs | Videos | SoundCloud`), the trailing "…" on song rows, the mini player with heart + play/pause (no skip button), Now Playing with chevron-down + "…" top row and the heart next to the title, Edit Info with Track and Disc, "Continue listening" in sentence case; anything else that differs from the app.
- **README images** (`docs/images/readme/*.png`, 780×1688, Coral) are re-rendered from the same screens by `tool/make_screenshots.sh` (headless Chromium, device scale 2).
- **Version and date** are fetched live from `api.github.com/repos/shiraayuki/owntune/releases/latest`; on failure the line reads "Latest release on GitHub" with a link.
- **Copy stays true to what ships:** no claim about update notices until the in-app update check (Distribution part 3) exists; the Android steps say to download the new APK the same way.

## Non-goals

No light-mode toggle on the page, no analytics, no build step (plain static files), no screenshots from the real app.

## Left to the builder

Iframe scaling (the screens are 390×844 CSS px; scale with `transform` to the phone width), lazy loading of the story screens, the exact wording of fallback text.
