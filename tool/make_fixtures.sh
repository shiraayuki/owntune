#!/usr/bin/env bash
# Generates the audio fixtures in test/fixtures/audio/.
#
# The output files are committed to the repository; re-run this script only
# when the fixture set changes. Requires ffmpeg (with libmp3lame, aac, flac,
# libvorbis) and python3. Existing files are overwritten.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/test/fixtures/audio"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$out"

# ffmpeg base command: overwrite, quiet.
ff=(ffmpeg -y -v error)
# Output options placed after the inputs: bit-exact output (no encoder version
# or timestamps in the files) and no metadata carried over from the inputs.
bx=(-fflags +bitexact -flags:a +bitexact -map_metadata -1)

# 1 s mono 8 kHz sine tone used as the audio source of every fixture.
sine=(-f lavfi -i "sine=frequency=440:sample_rate=8000:duration=1")

# 16x16 cover images (PNG for the MP3, JPEG for the FLAC).
img=(-f lavfi -i "color=c=0x3366cc:s=16x16:d=1")
"${ff[@]}" "${img[@]}" "${bx[@]}" -frames:v 1 "$tmp/cover.png"
"${ff[@]}" "${img[@]}" "${bx[@]}" -frames:v 1 "$tmp/cover.jpg"

# tagged.mp3: full ID3v2.3 tag set with an embedded PNG front cover (APIC).
"${ff[@]}" "${sine[@]}" -i "$tmp/cover.png" "${bx[@]}" \
  -map 0:a -map 1:v -c:a libmp3lame -b:a 32k -ar 8000 -ac 1 -c:v copy \
  -id3v2_version 3 \
  -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
  -metadata title="After the Rain" \
  -metadata artist="Juno Vale" \
  -metadata album="Paper Lanterns" \
  -metadata album_artist="Juno Vale" \
  -metadata track=2 \
  -metadata disc=1 \
  -metadata date=2021 \
  -metadata genre="Indie Folk" \
  "$out/tagged.mp3"

# tagged.flac: Vorbis comments with an embedded JPEG front cover (PICTURE block).
"${ff[@]}" "${sine[@]}" -i "$tmp/cover.jpg" "${bx[@]}" \
  -map 0:a -map 1:v -c:a flac -c:v copy -disposition:v attached_pic \
  -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
  -metadata title="Blue Hour" \
  -metadata artist="The Quiet Coast" \
  -metadata album="Low Tide Radio" \
  -metadata track=1 \
  -metadata date=2019 \
  "$out/tagged.flac"

# tagged.m4a: AAC in MP4 with basic tags and no cover.
"${ff[@]}" "${sine[@]}" "${bx[@]}" -c:a aac -b:a 32k -ar 8000 -ac 1 \
  -metadata title="Amber Lights" \
  -metadata artist="Neon Harbor" \
  -metadata album="Velvet Hours" \
  -metadata track=3 \
  -metadata date=2021 \
  "$out/tagged.m4a"

# dash.m4a: AAC in a DASH-fragmented MP4 (major brand "dash"), like the
# audio YouTube serves; title only, no cover. global_sidx keeps a real
# duration in the moov box (empty_moov would make lofty read 0 ms).
"${ff[@]}" "${sine[@]}" "${bx[@]}" -c:a aac -b:a 32k -ar 8000 -ac 1 \
  -movflags +frag_keyframe+global_sidx -brand dash \
  -metadata title="Rain Loop" \
  "$out/dash.m4a"

# demo_3.wav: plain PCM, no tags.
"${ff[@]}" "${sine[@]}" "${bx[@]}" -c:a pcm_s16le "$out/demo_3.wav"

# unicode.mp3: non-ASCII title/artist, no album.
"${ff[@]}" "${sine[@]}" "${bx[@]}" -c:a libmp3lame -b:a 32k -ar 8000 -ac 1 \
  -id3v2_version 3 \
  -metadata title="Grüße aus Köln" \
  -metadata artist="Ärzte & Söhne" \
  "$out/unicode.mp3"

# evening-walk.ogg: Vorbis with a title only.
"${ff[@]}" "${sine[@]}" "${bx[@]}" -c:a libvorbis -q:a 0 -ar 8000 -ac 1 \
  -metadata title="Evening Walk" \
  "$out/evening-walk.ogg"

# broken.mp3: 2 KB of pseudo-random bytes (fixed seed), not a valid MP3.
python3 - "$out/broken.mp3" <<'PY'
import random
import sys

rng = random.Random(1)
with open(sys.argv[1], "wb") as f:
    f.write(bytes(rng.getrandbits(8) for _ in range(2048)))
PY

echo "Fixtures written to $out"
