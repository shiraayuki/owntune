# Download page redesign

Approved 2026-11-25 ("das ist perfekt. setz das um!") after three directions and three combined sketches (kept outside the repo; the approved one was "Combined v3").

## Why

The user wanted the page "fancier", oriented on modern, bold product pages, while everything harmonises. German/Croatian translations were asked for first and then shelved (see the localization memory); English only for now.

## Approaches considered

- **A · Equalizer:** the icon's three bars fill the hero like a level meter, the wordmark runs across them. Loudest.
- **B · Record crate:** drifting wall of album covers, features as a self-playing tracklist.
- **C · Keynote:** centred headline over an accent aurora, a tilting phone, a grid of live tiles.

Picked by the user: **C's hero, B's top bar, A's feature chapters**, then refined: version as a visible badge, one phone that travels from the hero into the features, no level-meter bars beside the chapters.

## Design (as approved)

- **One typeface:** Geist (Google Fonts) for everything, replacing Unbounded + Hanken Grotesk. Colours stay Midnight + the app's accent (Coral default).
- **Top bar (from B):** logo mark + "owntune" left, Features / Install right; gains a blurred background once past the hero.
- **Aurora:** three blurred accent-derived blobs, `position: fixed` behind the whole page; its opacity dims as you scroll instead of ending, so there is no cut to black.
- **Hero (from C):** a glass badge above the headline, "**Version X.Y.Z** is out, released <date>", filled live from the GitHub API and linking to the release (fallback: "See the latest release"); headline "Your music. Your files. Your player."; sub line with "free"; Install on iPhone / Download for Android.
- **The one phone:** a single fixed phone. In the hero it starts tilted just below the buttons and straightens + settles centred as you scroll; when the features arrive it glides to a sticky slot on the right and stays beside the chapters, switching to the screen of the chapter nearest the middle (Home, Library, Player, Playlist, Download, Edit, Stats). On narrow screens (≤ 900 px) it scrolls away after the hero and each chapter shows its own small phone.
- **Feature chapters (from A):** large headline + paragraph, the active one bright, the others dimmed; no bars.

## Builder's calls (Claude)

- The rest follows the same language: the promise sentence with scroll-lit words stays (after the features), the accent picker section (recolours aurora, logo, buttons and the phone screens; the aurora brightens there again), install tabs with the filling step line, FAQ, footer and the mini player showing the current section and scroll progress. Copy is kept from the current page.
- Fix on the way: the stray `title=""None` attributes on the story iframes.
- `prefers-reduced-motion`: no aurora drift, no smooth scrolling; scroll-linked positions stay (they follow the user's scrolling, not a timer).

## Non-goals

No translations, no new copy claims, no change to `site/screens/` or the README images.
