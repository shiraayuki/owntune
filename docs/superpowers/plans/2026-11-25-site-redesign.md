# Download Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `site/index.html` in the approved design: Geist, fixed aurora, version badge, one travelling phone, chapters without bars, and the remaining sections in the same language.

**Architecture:** One static HTML file with inline CSS and JS, as today. The approved sketch `docs/mockups/site-v2/index.html` is the source for top bar, aurora, hero, phone and chapters; the current `site/index.html` is the source for all copy and for the promise, accent, install, FAQ, footer and mini player behaviour.

**Tech Stack:** HTML, CSS, vanilla JS; Geist from Google Fonts; screens in `site/screens/*.html` (unchanged).

**Spec:** `docs/superpowers/specs/2026-11-25-site-redesign-design.md`

## Global Constraints

- English only; copy kept from the current page, no new promises.
- Colours: Midnight tokens + `--accent` (default `#ff7a59`); every accent use reads `var(--accent)` so the picker recolours all of it, including the screens via `postMessage({ mode: 'dark', accent })`.
- Works at 390 px wide without horizontal scroll; ≤ 900 px uses inline phones per chapter.
- `prefers-reduced-motion`: no aurora drift, no smooth scroll.

## Review Focus

- GitHub API fails or is rate-limited (60 requests/h per IP): badge reads "See the latest release" and still links to `releases/latest`.
- Short viewport (e.g. 1280×640): the phone must fit; `--phone-w` is also capped by height: `min(330px, 74vw, (100svh - 140px) * 780 / 1688)`.
- Resizing across 900 px while scrolled into the features: the fixed phone and inline phones swap without a stuck or doubled phone.
- Accent change while deep in the page: aurora, logo, badge dot, install step line, mini player and all loaded iframes (fixed and inline) follow.
- Android user agent: the Android install tab is preselected; the hero buttons select their tab.

---

### Task 1: New `site/index.html`

**Files:**
- Modify: `site/index.html` (full rewrite)
- Reference: `docs/mockups/site-v2/index.html` (approved sketch; its screen paths point to `site/screens/`)

**Interfaces:**
- Consumes: `site/screens/*.html` accept `postMessage({ mode, accent })`.
- Produces: section ids `#features`, `#install`, `#faq` (README and links use `#install`).

- [x] **Step 1: Sections in order:** top bar (sketch) → hero with badge (sketch; badge text before fetch: "See the latest release") → `.features` with the seven chapters and the fixed `.device` (sketch, 7 screens) → promise sentence with scroll-lit words (current page, Geist, no `.promises` padding hack) → accent picker (current page; set `--glow` back up to ~0.6 while it is in view) → install tabs + steps (current page content verbatim) → FAQ (current) → footer (current) → mini player (current: names the section in view via `data-track`, progress bar, Install button hidden in the Install section).
- [x] **Step 2: JS:** one `frame()` on scroll/resize as in the sketch, extended by the current page's promise lighting, step line, mini player and tab logic; the release fetch writes "**Version X.Y.Z** is out, released <Month D>" into the badge and sets its `href` to `html_url`; `ResizeObserver` fit for every `.screen`; tint on iframe load and on accent change. No `title=""None`.
- [x] **Step 3: Verify visually** with headless Chromium through a scroll helper (iframe + `scrollTo`) at 1440×900, 1280×640 and 390×844, positions: top, hero end, two chapters, accent, install, FAQ. Expected: phone never overlaps the buttons or gets cut by a short viewport, no horizontal scroll at 390 px, Install section hides the mini player's button.
- [x] **Step 4: Verify the fallback:** block `api.github.com` (e.g. `--host-resolver-rules="MAP api.github.com 0.0.0.0"`); badge shows "See the latest release".
- [x] **Step 5: Commit** `site/index.html`, `docs/mockups/site-v2/`, spec and plan: `site: redesign the download page (one travelling phone, version badge)`.
