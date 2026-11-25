# Download Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the approved download page mockup into `site/` with live HTML phone screens that follow the page's accent, ready for GitHub Pages.

**Architecture:** Static files only. `site/index.html` (from `docs/mockups/distribution-v1/index.html`) embeds `site/screens/<name>.html` in iframes; the accent picker posts `{mode: 'dark', accent: 'rrggbb'}` to each iframe (handled by the copied `mockup.js`). `tool/make_screenshots.sh` renders the same screens to the README PNGs. `.github/workflows/pages.yml` deploys `site/`.

**Tech Stack:** HTML/CSS/vanilla JS, headless Chromium, GitHub Actions (`actions/upload-pages-artifact`, `actions/deploy-pages`).

**Spec:** `docs/superpowers/specs/2026-11-25-download-page-design.md`

## Global Constraints

- All text in English. No external scripts; fonts from Google Fonts only (as in the mockup).
- Screens are 390×844 CSS px; README PNGs 780×1688 (scale 2), Coral `ff7a59`.
- Every screen must match the current app (read the widget code), not the old mockups.
- Page must work at phone width (16 px gutter, no horizontal scroll) and with `prefers-reduced-motion`.

## Review Focus

- The accent picker recolours every embedded screen, including iframes that load after the click (lazy ones).
- A failed GitHub API call (offline, rate limit) leaves a sensible version line, no "undefined".
- Mobile: the inline phones in the chapters show their screens (they are separate iframes).
- The screens render identically from `file://` (local preview, screenshot script) and from Pages (relative paths only).
- Copy makes no promise the app does not keep (update notice, "sends nothing").

---

### Task 1: Screens

**Files:** Create `site/screens/{mockup,m2,roadmap,home,switch}.css`, `site/screens/{mockup,m2,roadmap,home}.js` (copies), `site/screens/{home,library,player,playlist,download,edit,stats}.html` (from home-v1/01-for-you, m2-v1/02-library-songs, m2-v1/09-player, roadmap-v1/12-playlist-detail, roadmap-v1/07-online-results-youtube, roadmap-v1/01-edit-cover, home-v1/03-stats), each including all shared CSS/JS by local path.

- [ ] Copy and re-point includes; open each in Chromium headless to check it renders like the old PNG.
- [ ] Correct each screen against the app code (list in the spec, plus whatever else differs).
- [ ] Commit `site: phone screens as HTML, matched to the app`.

### Task 2: Page

**Files:** Create `site/index.html` (from the mockup).

- [ ] Replace each `<img>` screen with `<iframe src="screens/<name>.html" loading="lazy" tabindex="-1" title="">` scaled to the phone; the pinned story phone swaps visible iframes.
- [ ] Accent picker: also `postMessage({mode: 'dark', accent})` to every iframe, and on each iframe's `load` (so lazy ones get the current colour).
- [ ] Live version line from the releases API (`tag_name` without `v`, `published_at` as "November 25"); fallback "Latest release on GitHub".
- [ ] Copy: Android step 3 and FAQ true to v0.8.2 (no update notice yet).
- [ ] Commit `site: download page`.

### Task 3: README screenshots

**Files:** Create `tool/make_screenshots.sh`; regenerate `docs/images/readme/*.png`.

- [ ] Script: for each screen, `chromium --headless --screenshot=<out> --window-size=390,844 --force-device-scale-factor=2 --hide-scrollbars file://…/site/screens/<name>.html`.
- [ ] Run it; view the PNGs.
- [ ] Commit `docs: README screenshots from the site screens`.

### Task 4: Pages workflow and docs

**Files:** Create `.github/workflows/pages.yml`; modify `CLAUDE.md` (Commands + Architecture: `site/`, `tool/make_screenshots.sh`).

- [ ] Workflow: on push to main with `paths: [site/**]` and `workflow_dispatch`; permissions `pages: write`, `id-token: write`; upload `site/` and deploy. Pages itself stays off until the APK release.
- [ ] Commit `ci: deploy site/ to GitHub Pages`.
