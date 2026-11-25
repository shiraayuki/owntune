#!/usr/bin/env bash
# Renders the download page's phone screens (site/screens/*.html) to PNGs,
# 780x1688 (390x844 at scale 2), in the app's default accent (Coral).
#
#   tool/make_screenshots.sh            # into docs/images/readme/
#   tool/make_screenshots.sh <out-dir>  # anywhere else, e.g. for a preview
#   ACCENT=5ab4ff tool/make_screenshots.sh <out-dir>
#
# Needs Chromium (chromium, chromium-browser or google-chrome on PATH).
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-docs/images/readme}"
accent="${ACCENT:-ff7a59}"
screens=(home library player playlist download edit stats)

browser=""
for b in chromium chromium-browser google-chrome; do
  if command -v "$b" >/dev/null; then browser="$b"; break; fi
done
[[ -n "$browser" ]] || { echo "Chromium not found" >&2; exit 1; }

mkdir -p "$out"
profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT
for s in "${screens[@]}"; do
  "$browser" --headless --disable-gpu --hide-scrollbars \
    --user-data-dir="$profile" \
    --window-size=390,844 --force-device-scale-factor=2 \
    --virtual-time-budget=2000 \
    --screenshot="$out/$s.png" \
    "file://$PWD/site/screens/$s.html?accent=$accent" 2>/dev/null
  echo "$out/$s.png"
done
