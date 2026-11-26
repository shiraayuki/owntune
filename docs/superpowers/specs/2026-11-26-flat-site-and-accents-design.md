# Flat download page and calmer accents (v0.9.1)

Approved 2026-11-26 ("okay perfekt bau dir farben in die app ein und dann push mit tag und release") after one draft (`docs/mockups/site-v3/index.html`) and one round of changes.

## Why

The user found the page still looked "a bit AI" because of its gradients, above all the aurora in the background, and wanted something plainer but modern that still fits the app. In a second step the accents themselves were "too lively"; the brightness of Spotify's and SoundCloud's colours fits better, and grey and white were wanted as choices.

## Site (supersedes the aurora/glass parts of 2026-11-25-site-redesign-design.md)

- No gradients, no blur/glass, no glow. Flat colours from the app: Midnight `#0e0e12` / `#1a1a21` / `#24242d`, and Paper.
- **The record:** one flat disc in the accent (two hairline grooves) behind the phone in the hero. It starts below the buttons, rises to the phone's centre and shrinks into the phone when the phone glides to the feature chapters. It is the only loud element.
- **Paper or Midnight, in your colour:** the accent section is a settings card like the app's (Appearance Paper | Midnight, Accent). Paper switches the whole page and the phone screens to the light, black-and-white look (the disc turns black like vinyl) and disables the accents, as in the app.
- Install: the app's text tabs with an accent underline; "what you need" as a settings-style card (name left, detail right; stacked on phones). Steps, FAQ, mini player, phone choreography and copy are unchanged.

## Accents (app and site)

| Name | Hex | Replaces |
|---|---|---|
| Coral (default) | `#ff6b4a` | Coral `#ff7a59` |
| Amber | `#f0a020` | Amber `#ffb340` |
| Green | `#1ed760` | Lime `#c6f432`, Teal `#3ee0c4` |
| Blue | `#4d8dff` | Sky `#5ab4ff` |
| Violet | `#9b6bff` | Violet `#b38cff` |
| Pink | `#f0509a` | Pink `#ff6fb5` |
| Grey | `#a1a1aa` | new |
| White | `#f4f2ef` | new |

Dark text on every accent has at least 5.4:1. A stored old accent maps to its successor (`kLegacyAccents`), so an update keeps the user's choice; any other stored value that is no preset falls back to Coral. The app icon keeps its colour (`tool/make_icons.sh`).
